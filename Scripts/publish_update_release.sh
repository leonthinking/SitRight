#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GH_REPOSITORY="leonthinking/SitRight"
EXPECTED_ORIGIN_HTTPS="https://github.com/leonthinking/SitRight.git"
EXPECTED_ORIGIN_SSH="git@github.com:leonthinking/SitRight.git"
EXPECTED_FEED_URL="https://github.com/leonthinking/SitRight/releases/latest/download/appcast.xml"
EXPECTED_TEAM_IDENTIFIER="973KFG9CL9"
EXPECTED_APP_GROUP="973KFG9CL9.com.leon.SitRight"
EXPECTED_INSTALLER_MACH_SERVICE="com.leon.SitRight-spki"
EXPECTED_STATUS_MACH_SERVICE="com.leon.SitRight-spks"
SPARKLE_RELEASE_VERSION="2.9.2"
SPARKLE_TOOLS_ARCHIVE_URL="https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_RELEASE_VERSION/Sparkle-for-Swift-Package-Manager.zip"
EXPECTED_SPARKLE_TOOLS_ARCHIVE_SHA256="b83e37436774556ed055e0244b297ef2c790e0737393bf65bf495fcbba6eed65"
SPARKLE_KEY_ACCOUNT="${SITRIGHT_SPARKLE_KEY_ACCOUNT:-com.leon.SitRight}"
SPARKLE_TOOLS_DIR=""
GENERATE_APPCAST=""
GENERATE_KEYS=""
SIGN_UPDATE=""
SPARKLE_TOOLS_ARCHIVE_SHA256=""
GENERATE_APPCAST_SHA256=""
GENERATE_KEYS_SHA256=""
SIGN_UPDATE_SHA256=""
PUBLICATION_STATE_DIR="$ROOT_DIR/build/.SitRightReleasePublication"
PUBLICATION_STATE_FILE="$PUBLICATION_STATE_DIR/state"
PUBLICATION_IN_PROGRESS=0
PUBLICATION_TAG=""
TEMP_DIR=""
MOUNT_POINT=""
ATTACHED_DEVICE=""

cleanup() {
  local exit_status="$?"

  trap - EXIT HUP INT TERM
  if [ -n "$ATTACHED_DEVICE" ]; then
    /usr/bin/hdiutil detach "$ATTACHED_DEVICE" >/dev/null 2>&1 ||
      exit_status=1
  fi
  if [ "$exit_status" != "0" ] &&
    [ "$PUBLICATION_IN_PROGRESS" = "1" ]; then
    if ! recover_publication_to_draft "$PUBLICATION_TAG"; then
      echo "error: Release publication state is uncertain; inspect $PUBLICATION_STATE_FILE before retrying" >&2
      exit_status=1
    fi
  fi
  if [ -n "$TEMP_DIR" ]; then
    /bin/chmod -R u+w "$TEMP_DIR" >/dev/null 2>&1 || true
    rm -rf "$TEMP_DIR"
  fi
  exit "$exit_status"
}

manifest_value() {
  local key="$1"
  local manifest="$2"

  /usr/bin/sed -n "s/^$key=//p" "$manifest" | /usr/bin/head -1
}

manifest_asset_name() {
  local key="$1"
  local manifest="$2"
  local value

  value="$(manifest_value "$key" "$manifest")"
  case "$value" in
    "" | "." | ".." | */*)
      echo "error: invalid $key asset name in release manifest" >&2
      return 1
      ;;
  esac
  /usr/bin/printf '%s\n' "$value"
}

validate_sha256_value() {
  local value="$1"
  local label="$2"

  case "$value" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*)
      ;;
    *)
      echo "error: $label is not a lowercase SHA-256 value" >&2
      return 1
      ;;
  esac
  if [ "${#value}" != "64" ] || [[ "$value" == *[!0-9a-f]* ]]; then
    echo "error: $label is not a lowercase SHA-256 value" >&2
    return 1
  fi
}

prepare_verified_sparkle_tools() {
  local destination_root="$1"
  local archive_path="$destination_root/Sparkle-for-Swift-Package-Manager.zip"
  local extraction_root="$destination_root/sparkle-tools"
  local tool

  /usr/bin/curl \
    --fail \
    --location \
    --proto '=https' \
    --tlsv1.2 \
    --silent \
    --show-error \
    --output "$archive_path" \
    "$SPARKLE_TOOLS_ARCHIVE_URL"
  SPARKLE_TOOLS_ARCHIVE_SHA256="$(
    /usr/bin/shasum -a 256 "$archive_path" |
      /usr/bin/awk '{print $1}'
  )"
  if [ "$SPARKLE_TOOLS_ARCHIVE_SHA256" != "$EXPECTED_SPARKLE_TOOLS_ARCHIVE_SHA256" ]; then
    echo "error: downloaded Sparkle tools archive failed the pinned SwiftPM checksum" >&2
    return 1
  fi

  /bin/mkdir "$extraction_root"
  /usr/bin/ditto -x -k "$archive_path" "$extraction_root"
  SPARKLE_TOOLS_DIR="$extraction_root/bin"
  GENERATE_APPCAST="$SPARKLE_TOOLS_DIR/generate_appcast"
  GENERATE_KEYS="$SPARKLE_TOOLS_DIR/generate_keys"
  SIGN_UPDATE="$SPARKLE_TOOLS_DIR/sign_update"
  for tool in "$GENERATE_APPCAST" "$GENERATE_KEYS" "$SIGN_UPDATE"; do
    if [ ! -f "$tool" ] || [ -L "$tool" ] || [ ! -x "$tool" ]; then
      echo "error: verified Sparkle archive is missing a regular executable release tool" >&2
      return 1
    fi
  done
  /bin/chmod -R a-w "$extraction_root"

  GENERATE_APPCAST_SHA256="$(
    /usr/bin/shasum -a 256 "$GENERATE_APPCAST" |
      /usr/bin/awk '{print $1}'
  )"
  GENERATE_KEYS_SHA256="$(
    /usr/bin/shasum -a 256 "$GENERATE_KEYS" |
      /usr/bin/awk '{print $1}'
  )"
  SIGN_UPDATE_SHA256="$(
    /usr/bin/shasum -a 256 "$SIGN_UPDATE" |
      /usr/bin/awk '{print $1}'
  )"
}

publication_state_value() {
  local key="$1"

  /usr/bin/sed -n "s/^$key=//p" "$PUBLICATION_STATE_FILE" |
    /usr/bin/head -1
}

write_publication_state() {
  local tag="$1"
  local commit_sha="$2"
  local state_candidate

  if [ -L "$PUBLICATION_STATE_DIR" ] ||
    [ -L "$PUBLICATION_STATE_FILE" ]; then
    echo "error: publication recovery state must not use symlinks" >&2
    return 1
  fi
  /bin/mkdir -p "$PUBLICATION_STATE_DIR"
  state_candidate="$PUBLICATION_STATE_DIR/.state.$$"
  /usr/bin/printf 'tag=%s\ncommit=%s\n' "$tag" "$commit_sha" \
    >"$state_candidate"
  /bin/chmod 600 "$state_candidate"
  /bin/mv "$state_candidate" "$PUBLICATION_STATE_FILE"
}

clear_publication_state() {
  if [ -L "$PUBLICATION_STATE_FILE" ]; then
    echo "error: refusing to remove a symlinked publication recovery state" >&2
    return 1
  fi
  if [ -f "$PUBLICATION_STATE_FILE" ]; then
    /bin/rm -f "$PUBLICATION_STATE_FILE"
  fi
  /bin/rmdir "$PUBLICATION_STATE_DIR" >/dev/null 2>&1 || true
}

recover_publication_to_draft() {
  local tag="$1"
  local state_json
  local is_draft

  if [ -z "$tag" ]; then
    echo "error: publication recovery state has no tag" >&2
    return 1
  fi
  if ! state_json="$(
    gh release view "$tag" \
      --repo "$GH_REPOSITORY" \
      --json tagName,isDraft,isPrerelease
  )"; then
    echo "error: could not determine whether Release $tag is public" >&2
    return 1
  fi
  is_draft="$(
    /usr/bin/python3 -c '
import json
import sys
print("true" if json.load(sys.stdin)["isDraft"] else "false")
' <<<"$state_json"
  )"
  if [ "$is_draft" != "true" ]; then
    if ! gh release edit "$tag" \
      --repo "$GH_REPOSITORY" \
      --draft=true; then
      echo "error: could not restore Release $tag to Draft" >&2
      return 1
    fi
    if ! state_json="$(
      gh release view "$tag" \
        --repo "$GH_REPOSITORY" \
        --json tagName,isDraft,isPrerelease
    )"; then
      echo "error: could not verify recovery of Release $tag" >&2
      return 1
    fi
    is_draft="$(
      /usr/bin/python3 -c '
import json
import sys
print("true" if json.load(sys.stdin)["isDraft"] else "false")
' <<<"$state_json"
    )"
    if [ "$is_draft" != "true" ]; then
      echo "error: Release $tag remains public after recovery" >&2
      return 1
    fi
  fi
  clear_publication_state
  PUBLICATION_IN_PROGRESS=0
}

recover_pending_publication() {
  local expected_tag="$1"
  local expected_commit="$2"
  local pending_tag
  local pending_commit
  local pending_remote_commit

  if [ ! -e "$PUBLICATION_STATE_FILE" ]; then
    return 0
  fi
  if [ ! -f "$PUBLICATION_STATE_FILE" ] ||
    [ -L "$PUBLICATION_STATE_FILE" ]; then
    echo "error: invalid publication recovery state at $PUBLICATION_STATE_FILE" >&2
    return 1
  fi
  pending_tag="$(publication_state_value tag)"
  pending_commit="$(publication_state_value commit)"
  case "$pending_tag" in
    v[0-9]*)
      ;;
    *)
      echo "error: invalid tag in publication recovery state" >&2
      return 1
      ;;
  esac
  if [ "${#pending_commit}" != "40" ] ||
    [[ "$pending_commit" == *[!0-9a-f]* ]]; then
    echo "error: invalid commit in publication recovery state" >&2
    return 1
  fi
  if [ "$pending_tag" != "$expected_tag" ] ||
    [ "$pending_commit" != "$expected_commit" ]; then
    echo "error: publication recovery state does not match the current release manifest; inspect it manually" >&2
    return 1
  fi
  pending_remote_commit="$(
    git -C "$ROOT_DIR" ls-remote origin "refs/tags/$pending_tag^{}" |
      /usr/bin/awk 'NR == 1 { print $1 }'
  )"
  if [ -z "$pending_remote_commit" ]; then
    pending_remote_commit="$(
      git -C "$ROOT_DIR" ls-remote origin "refs/tags/$pending_tag" |
        /usr/bin/awk 'NR == 1 { print $1 }'
    )"
  fi
  if [ "$pending_remote_commit" != "$pending_commit" ]; then
    echo "error: publication recovery state does not match the remote tag; inspect it manually" >&2
    return 1
  fi
  echo "Recovering interrupted publication for $pending_tag as Draft"
  recover_publication_to_draft "$pending_tag"
}

validate_origin_url() {
  local url="$1"
  local label="$2"

  case "$url" in
    "$EXPECTED_ORIGIN_HTTPS" | "${EXPECTED_ORIGIN_HTTPS%.git}" | "$EXPECTED_ORIGIN_SSH" | "${EXPECTED_ORIGIN_SSH%.git}")
      ;;
    *)
      echo "error: $label must point to $GH_REPOSITORY, got $url" >&2
      return 1
      ;;
  esac
}

team_identifier_for() {
  local target="$1"

  /usr/bin/codesign -dv "$target" 2>&1 |
    /usr/bin/sed -n 's/^TeamIdentifier=//p' |
    /usr/bin/head -1
}

verify_no_debug_entitlement() {
  local target="$1"
  local label="$2"
  local entitlements
  local debug_allowed

  entitlements="$(/usr/bin/codesign -d --entitlements :- "$target" 2>/dev/null)" ||
    return 1
  debug_allowed="$(
    /usr/bin/plutil \
      -extract "com\\.apple\\.security\\.get-task-allow" \
      raw \
      -o - \
      - <<<"$entitlements" 2>/dev/null || true
  )"
  if [ "$debug_allowed" = "true" ]; then
    echo "error: $label contains com.apple.security.get-task-allow" >&2
    return 1
  fi
}

verify_exact_entitlements() {
  local target="$1"
  local label="$2"
  local role="$3"
  local entitlements
  local sandbox_enabled
  local group_index=0
  local group_value
  local mach_index=0
  local mach_value
  local installer_service_found=0
  local status_service_found=0

  entitlements="$(/usr/bin/codesign -d --entitlements :- "$target" 2>/dev/null)" ||
    return 1
  sandbox_enabled="$(
    /usr/bin/plutil \
      -extract "com\\.apple\\.security\\.app-sandbox" \
      raw \
      -o - \
      - <<<"$entitlements" 2>/dev/null || true
  )"
  if [ "$sandbox_enabled" != "true" ]; then
    echo "error: $label must enable App Sandbox" >&2
    return 1
  fi

  while group_value="$(
    /usr/bin/plutil \
      -extract "com\\.apple\\.security\\.application-groups.$group_index" \
      raw \
      -o - \
      - <<<"$entitlements" 2>/dev/null
  )"; do
    if [ "$group_value" != "$EXPECTED_APP_GROUP" ]; then
      echo "error: $label contains an unexpected App Group" >&2
      return 1
    fi
    group_index=$((group_index + 1))
  done
  if [ "$group_index" != "1" ]; then
    echo "error: $label must contain exactly one App Group" >&2
    return 1
  fi

  while mach_value="$(
    /usr/bin/plutil \
      -extract "com\\.apple\\.security\\.temporary-exception\\.mach-lookup\\.global-name.$mach_index" \
      raw \
      -o - \
      - <<<"$entitlements" 2>/dev/null
  )"; do
    case "$mach_value" in
      "$EXPECTED_INSTALLER_MACH_SERVICE")
        installer_service_found=$((installer_service_found + 1))
        ;;
      "$EXPECTED_STATUS_MACH_SERVICE")
        status_service_found=$((status_service_found + 1))
        ;;
      *)
        echo "error: $label contains an unexpected Mach lookup service" >&2
        return 1
        ;;
    esac
    mach_index=$((mach_index + 1))
  done

  if [ "$role" = "app" ]; then
    if [ "$mach_index" != "2" ] ||
      [ "$installer_service_found" != "1" ] ||
      [ "$status_service_found" != "1" ]; then
      echo "error: $label must contain the exact Sparkle Mach services" >&2
      return 1
    fi
  elif [ "$role" = "widget" ]; then
    if [ "$mach_index" != "0" ]; then
      echo "error: $label must not contain Sparkle Mach services" >&2
      return 1
    fi
  else
    echo "error: unsupported entitlement role $role" >&2
    return 1
  fi
}

verify_signed_target() {
  local target="$1"
  local label="$2"

  if [ ! -e "$target" ]; then
    echo "error: missing $label: $target" >&2
    return 1
  fi
  /usr/bin/codesign --verify --strict "$target"
  if [ "$(team_identifier_for "$target")" != "$EXPECTED_TEAM_IDENTIFIER" ]; then
    echo "error: $label has the wrong TeamIdentifier" >&2
    return 1
  fi
  verify_no_debug_entitlement "$target" "$label"
}

verify_release_app() {
  local app_path="$1"
  local version="$2"
  local build_version="$3"
  local widget_path="$app_path/Contents/PlugIns/SitRightWidgetExtension.appex"
  local framework="$app_path/Contents/Frameworks/Sparkle.framework"
  local framework_version="$framework/Versions/Current"
  local target
  local label
  local expected_public_key
  local setting_key
  local expected_setting_value
  local actual_setting_value

  if [ "$(
    /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
      "$app_path/Contents/Info.plist"
  )" != "com.leon.SitRight" ] ||
    [ "$(
      /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
        "$widget_path/Contents/Info.plist"
    )" != "com.leon.SitRight.SitRightWidgetExtension" ]; then
    echo "error: release archive contains an unexpected bundle identifier" >&2
    return 1
  fi

  for plist in \
    "$app_path/Contents/Info.plist" \
    "$widget_path/Contents/Info.plist"; do
    if [ "$(
      /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist"
    )" != "$version" ] ||
      [ "$(
        /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist"
      )" != "$build_version" ]; then
      echo "error: release archive version/build mismatch" >&2
      return 1
    fi
  done

  if [ "$(
    /usr/libexec/PlistBuddy -c "Print :SUFeedURL" \
      "$app_path/Contents/Info.plist"
  )" != "$EXPECTED_FEED_URL" ]; then
    echo "error: release archive contains the wrong Sparkle Feed" >&2
    return 1
  fi
  expected_public_key="$(
    /usr/bin/plutil -extract SUPublicEDKey raw -o - \
      "$ROOT_DIR/AppBundle/Info.plist"
  )"
  if [ "$(
    /usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" \
      "$app_path/Contents/Info.plist"
  )" != "$expected_public_key" ]; then
    echo "error: release archive contains the wrong Sparkle public key" >&2
    return 1
  fi
  while IFS='|' read -r setting_key expected_setting_value; do
    actual_setting_value="$(
      /usr/bin/plutil \
        -extract "$setting_key" \
        raw \
        -o - \
        "$app_path/Contents/Info.plist" 2>/dev/null || true
    )"
    if [ "$actual_setting_value" != "$expected_setting_value" ]; then
      echo "error: release archive contains an unsafe Sparkle setting: $setting_key" >&2
      return 1
    fi
  done <<EOF
SURequireSignedFeed|true
SUVerifyUpdateBeforeExtraction|true
SUSignedFeedFailureExpirationInterval|0
SUEnableDownloaderService|true
SUEnableInstallerLauncherService|true
SUAutomaticallyUpdate|false
SUAllowsAutomaticUpdates|false
SUEnableAutomaticChecks|true
SUScheduledCheckInterval|86400
EOF

  if [ "$(/usr/bin/lipo -archs "$app_path/Contents/MacOS/SitRight")" != "arm64" ] ||
    [ "$(
      /usr/bin/lipo -archs \
        "$widget_path/Contents/MacOS/SitRightWidgetExtension"
    )" != "arm64" ]; then
    echo "error: release archive must contain arm64-only App and Widget binaries" >&2
    return 1
  fi

  verify_signed_target "$app_path" "SitRight.app"
  verify_exact_entitlements "$app_path" "SitRight.app" app
  verify_signed_target "$widget_path" "SitRightWidgetExtension.appex"
  verify_exact_entitlements "$widget_path" "SitRightWidgetExtension.appex" widget

  while IFS='|' read -r target label; do
    verify_signed_target "$target" "$label"
  done <<EOF
$framework_version/XPCServices/Downloader.xpc|Sparkle Downloader.xpc
$framework_version/XPCServices/Installer.xpc|Sparkle Installer.xpc
$framework_version/Updater.app|Sparkle Updater.app
$framework_version/Autoupdate|Sparkle Autoupdate
$framework|Sparkle.framework
EOF
  /usr/bin/codesign --verify --strict --deep "$app_path"
}

verify_update_zip_contents() {
  local archive_path="$1"
  local entry
  local entry_count=0

  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    entry_count=$((entry_count + 1))
    case "$entry" in
      SitRight.app | SitRight.app/*)
        ;;
      *)
        echo "error: update ZIP must contain only the SitRight.app hierarchy" >&2
        return 1
        ;;
    esac
    case "/$entry/" in
      */../*)
        echo "error: update ZIP contains a parent-directory path" >&2
        return 1
        ;;
    esac
  done < <(/usr/bin/unzip -Z1 "$archive_path")

  if [ "$entry_count" = "0" ]; then
    echo "error: update ZIP is empty" >&2
    return 1
  fi
}

verify_checksum_contract() {
  local release_dir="$1"
  local checksums_name="$2"
  local dmg_name="$3"
  local zip_name="$4"
  local appcast_name="$5"

  /usr/bin/python3 -c '
import re
import sys
from pathlib import Path

checksum_path = Path(sys.argv[1])
expected = set(sys.argv[2:])
actual = []
for raw_line in checksum_path.read_text(encoding="utf-8").splitlines():
    match = re.fullmatch(r"([0-9a-fA-F]{64})[ \t]+(?:[ *])?([^/]+)", raw_line)
    if match is None:
        raise SystemExit("checksum manifest contains an invalid line")
    actual.append(match.group(2))
if len(actual) != len(expected) or set(actual) != expected:
    raise SystemExit(
        f"checksum manifest must cover exactly {sorted(expected)}, got {sorted(actual)}"
    )
' \
    "$release_dir/$checksums_name" \
    "$dmg_name" \
    "$zip_name" \
    "$appcast_name"
  (
    cd "$release_dir"
    /usr/bin/shasum -a 256 -c "$checksums_name"
  )
}

verify_release_json() {
  local release_json="$1"
  local expected_draft="$2"
  local tag="$3"
  local dmg_name="$4"
  local zip_name="$5"
  local appcast_name="$6"
  local checksums_name="$7"

  /usr/bin/python3 -c '
import json
import sys

payload = json.load(sys.stdin)
expected_draft = sys.argv[1] == "true"
expected_tag = sys.argv[2]
expected_assets = set(sys.argv[3:])
actual_assets = {asset["name"] for asset in payload["assets"]}
if payload["tagName"] != expected_tag:
    raise SystemExit("release tag differs from the verified tag")
if payload["isDraft"] != expected_draft or payload["isPrerelease"]:
    raise SystemExit("release publication state differs from the expected gate")
if actual_assets != expected_assets:
    raise SystemExit(
        f"release assets differ: expected={sorted(expected_assets)} "
        f"actual={sorted(actual_assets)}"
    )
' \
    "$expected_draft" \
    "$tag" \
    "$dmg_name" \
    "$zip_name" \
    "$appcast_name" \
    "$checksums_name" <<<"$release_json"
}

github_api_json_or_404() {
  local endpoint="$1"
  local output_file="$2"
  local error_file="$3"

  if gh api \
    --hostname github.com \
    "$endpoint" \
    >"$output_file" \
    2>"$error_file"; then
    return 0
  fi
  if /usr/bin/grep -Eq '\(HTTP 404\)[[:space:]]*$' "$error_file"; then
    return 4
  fi
  echo "error: GitHub API request failed for $endpoint" >&2
  return 1
}

verify_prepared_assets() {
  local release_dir="$1"
  local tag="$2"
  local version="$3"
  local build_version="$4"
  local dmg_name="$5"
  local zip_name="$6"
  local appcast_name="$7"
  local checksums_name="$8"
  local appcast_path="$release_dir/$appcast_name"
  local zip_path="$release_dir/$zip_name"
  local dmg_path="$release_dir/$dmg_name"
  local enclosure_count
  local enclosure_url
  local enclosure_signature
  local enclosure_length
  local actual_zip_length
  local appcast_version
  local appcast_short_version
  local extracted_dir="$TEMP_DIR/extracted"
  local extracted_app="$extracted_dir/SitRight.app"
  local attach_output
  local mounted_entry_count
  local zip_cdhash
  local dmg_cdhash

  for asset in "$dmg_name" "$zip_name" "$appcast_name" "$checksums_name"; do
    if [ ! -f "$release_dir/$asset" ]; then
      echo "error: release asset is missing: $asset" >&2
      return 1
    fi
  done
  verify_checksum_contract \
    "$release_dir" \
    "$checksums_name" \
    "$dmg_name" \
    "$zip_name" \
    "$appcast_name"

  /usr/bin/xmllint --noout "$appcast_path"
  "$SIGN_UPDATE" \
    --account "$SPARKLE_KEY_ACCOUNT" \
    --verify \
    "$appcast_path"
  enclosure_count="$(
    /usr/bin/xmllint \
      --xpath \
      'count(//*[local-name()="enclosure"])' \
      "$appcast_path"
  )"
  enclosure_url="$(
    /usr/bin/xmllint \
      --xpath \
      'string(//*[local-name()="enclosure"]/@url)' \
      "$appcast_path"
  )"
  enclosure_signature="$(
    /usr/bin/xmllint \
      --xpath \
      'string(//*[local-name()="enclosure"]/@*[local-name()="edSignature"])' \
      "$appcast_path"
  )"
  enclosure_length="$(
    /usr/bin/xmllint \
      --xpath \
      'string(//*[local-name()="enclosure"]/@length)' \
      "$appcast_path"
  )"
  appcast_version="$(
    /usr/bin/xmllint \
      --xpath \
      'string(//*[local-name()="item"]/*[local-name()="version"])' \
      "$appcast_path"
  )"
  appcast_short_version="$(
    /usr/bin/xmllint \
      --xpath \
      'string(//*[local-name()="item"]/*[local-name()="shortVersionString"])' \
      "$appcast_path"
  )"
  actual_zip_length="$(/usr/bin/stat -f '%z' "$zip_path")"
  if [ "$enclosure_count" != "1" ] ||
    [ "$enclosure_url" != "https://github.com/$GH_REPOSITORY/releases/download/$tag/$zip_name" ] ||
    [ "$appcast_version" != "$build_version" ] ||
    [ "$appcast_short_version" != "$version" ] ||
    [ "$enclosure_length" != "$actual_zip_length" ] ||
    [ -z "$enclosure_signature" ]; then
    echo "error: appcast enclosure does not match the reviewed release assets" >&2
    return 1
  fi
  "$SIGN_UPDATE" \
    --account "$SPARKLE_KEY_ACCOUNT" \
    --verify \
    "$zip_path" \
    "$enclosure_signature"

  verify_update_zip_contents "$zip_path"
  /bin/mkdir "$extracted_dir"
  /usr/bin/ditto -x -k "$zip_path" "$extracted_dir"
  if [ "$(
    /usr/bin/find "$extracted_dir" -mindepth 1 -maxdepth 1 -print |
      /usr/bin/wc -l |
      /usr/bin/tr -d ' '
  )" != "1" ] ||
    [ ! -d "$extracted_app" ]; then
    echo "error: extracted update must contain only SitRight.app" >&2
    return 1
  fi
  verify_release_app "$extracted_app" "$version" "$build_version"

  /usr/bin/hdiutil verify "$dmg_path" >/dev/null
  MOUNT_POINT="$TEMP_DIR/dmg-mount"
  /bin/mkdir "$MOUNT_POINT"
  attach_output="$(
    /usr/bin/hdiutil attach \
      -readonly \
      -nobrowse \
      -mountpoint "$MOUNT_POINT" \
      "$dmg_path"
  )"
  ATTACHED_DEVICE="$(
    /usr/bin/awk '/^\/dev\// { device = $1 } END { print device }' \
      <<<"$attach_output"
  )"
  if [ -z "$ATTACHED_DEVICE" ]; then
    echo "error: failed to mount the release DMG" >&2
    return 1
  fi
  mounted_entry_count="$(
    /usr/bin/find "$MOUNT_POINT" -mindepth 1 -maxdepth 1 -print |
      /usr/bin/wc -l |
      /usr/bin/tr -d ' '
  )"
  if [ "$mounted_entry_count" != "2" ] ||
    [ ! -d "$MOUNT_POINT/SitRight.app" ] ||
    [ ! -L "$MOUNT_POINT/Applications" ] ||
    [ "$(/usr/bin/readlink "$MOUNT_POINT/Applications")" != "/Applications" ]; then
    echo "error: release DMG must contain only SitRight.app and Applications" >&2
    return 1
  fi
  verify_release_app \
    "$MOUNT_POINT/SitRight.app" \
    "$version" \
    "$build_version"
  zip_cdhash="$(
    /usr/bin/codesign -dv --verbose=4 "$extracted_app" 2>&1 |
      /usr/bin/sed -n 's/^CDHash=//p' |
      /usr/bin/head -1
  )"
  dmg_cdhash="$(
    /usr/bin/codesign -dv --verbose=4 "$MOUNT_POINT/SitRight.app" 2>&1 |
      /usr/bin/sed -n 's/^CDHash=//p' |
      /usr/bin/head -1
  )"
  if [ -z "$zip_cdhash" ] || [ "$zip_cdhash" != "$dmg_cdhash" ]; then
    echo "error: DMG and ZIP contain different SitRight.app candidates" >&2
    return 1
  fi
  /usr/bin/hdiutil detach "$ATTACHED_DEVICE" >/dev/null
  ATTACHED_DEVICE=""
  MOUNT_POINT=""
}

main() {
  local release_dir="${1:-}"
  local source_release_dir
  local immutable_release_dir
  local immutable_notes_file
  local manifest
  local tag
  local version
  local build_version
  local commit_sha
  local release_notes_sha256
  local actual_release_notes_sha256
  local expected_sparkle_tools_archive_sha256
  local expected_generate_appcast_sha256
  local expected_generate_keys_sha256
  local expected_sign_update_sha256
  local current_commit
  local local_tag_commit
  local remote_tag_commit
  local remote_tag_commit_after
  local origin_fetch_url
  local origin_push_url
  local notes_file="${SITRIGHT_RELEASE_NOTES_FILE:-}"
  local dmg_name
  local zip_name
  local appcast_name
  local checksums_name
  local expected_dmg_name
  local expected_zip_name
  local asset
  local api_status
  local target_release_file
  local latest_release_file
  local github_api_error_file
  local release_json
  local draft_release_json
  local latest_release_json
  local latest_tag
  local latest_has_appcast
  local latest_appcast
  local latest_build
  local release_status
  local final_release_status
  local remote_asset_dir
  local latest_after_publish_json

  if [ -z "$release_dir" ] || [ ! -d "$release_dir" ]; then
    echo "error: pass a prepared community-release directory" >&2
    return 1
  fi
  trap cleanup EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  source_release_dir="$(cd "$release_dir" && pwd)"
  if [ ! -f "$source_release_dir/RELEASE-MANIFEST" ] ||
    [ -L "$source_release_dir/RELEASE-MANIFEST" ]; then
    echo "error: release manifest is missing" >&2
    return 1
  fi
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/SitRightReleaseCheck.XXXXXX")"
  immutable_release_dir="$TEMP_DIR/prepared-assets"
  /bin/mkdir "$immutable_release_dir"
  manifest="$immutable_release_dir/RELEASE-MANIFEST"
  /usr/bin/ditto \
    --norsrc \
    "$source_release_dir/RELEASE-MANIFEST" \
    "$manifest"

  tag="$(manifest_value tag "$manifest")"
  version="$(manifest_value version "$manifest")"
  build_version="$(manifest_value build "$manifest")"
  commit_sha="$(manifest_value commit "$manifest")"
  release_notes_sha256="$(manifest_value release_notes_sha256 "$manifest")"
  expected_sparkle_tools_archive_sha256="$(
    manifest_value sparkle_tools_archive_sha256 "$manifest"
  )"
  expected_generate_appcast_sha256="$(
    manifest_value generate_appcast_sha256 "$manifest"
  )"
  expected_generate_keys_sha256="$(
    manifest_value generate_keys_sha256 "$manifest"
  )"
  expected_sign_update_sha256="$(
    manifest_value sign_update_sha256 "$manifest"
  )"
  dmg_name="$(manifest_asset_name dmg "$manifest")"
  zip_name="$(manifest_asset_name zip "$manifest")"
  appcast_name="$(manifest_asset_name appcast "$manifest")"
  checksums_name="$(manifest_asset_name checksums "$manifest")"
  expected_dmg_name="SitRight-$version-build$build_version-arm64.dmg"
  expected_zip_name="SitRight-$version-build$build_version-arm64.zip"
  if [ "$dmg_name" != "$expected_dmg_name" ] ||
    [ "$zip_name" != "$expected_zip_name" ] ||
    [ "$appcast_name" != "appcast.xml" ] ||
    [ "$checksums_name" != "SHA256SUMS" ]; then
    echo "error: release manifest contains unexpected asset names" >&2
    return 1
  fi

  case "$tag" in
    v[0-9]*)
      ;;
    *)
      echo "error: invalid release tag in release manifest" >&2
      return 1
      ;;
  esac
  case "$tag" in
    *[!A-Za-z0-9._-]*)
      echo "error: invalid release tag in release manifest" >&2
      return 1
      ;;
  esac
  if [ "${SITRIGHT_RELEASE_CONFIRMATION:-}" != "$tag" ]; then
    echo "error: set SITRIGHT_RELEASE_CONFIRMATION=$tag only after reviewing the assets" >&2
    return 1
  fi
  if [ -z "$notes_file" ] || [ ! -f "$notes_file" ]; then
    echo "error: SITRIGHT_RELEASE_NOTES_FILE must name a reviewed release-notes file" >&2
    return 1
  fi
  if [ -L "$notes_file" ]; then
    echo "error: release notes must be a regular file, not a symlink" >&2
    return 1
  fi
  immutable_notes_file="$TEMP_DIR/release-notes.md"
  /usr/bin/ditto --norsrc "$notes_file" "$immutable_notes_file"
  notes_file="$immutable_notes_file"
  for asset in "$dmg_name" "$zip_name" "$appcast_name" "$checksums_name"; do
    if [ ! -f "$source_release_dir/$asset" ] ||
      [ -L "$source_release_dir/$asset" ]; then
      echo "error: release asset must be a regular file: $asset" >&2
      return 1
    fi
    /usr/bin/ditto \
      --norsrc \
      "$source_release_dir/$asset" \
      "$immutable_release_dir/$asset"
  done
  release_dir="$immutable_release_dir"
  actual_release_notes_sha256="$(
    /usr/bin/shasum -a 256 "$notes_file" |
      /usr/bin/awk '{print $1}'
  )"
  if [ -z "$release_notes_sha256" ] ||
    [ "$actual_release_notes_sha256" != "$release_notes_sha256" ]; then
    echo "error: release notes differ from the copy embedded in the signed appcast" >&2
    return 1
  fi
  case "$build_version" in
    "" | *[!0-9]*)
      echo "error: CFBundleVersion must be an increasing integer" >&2
      return 1
      ;;
  esac
  validate_sha256_value \
    "$expected_sparkle_tools_archive_sha256" \
    "Sparkle tools archive hash"
  validate_sha256_value \
    "$expected_generate_appcast_sha256" \
    "generate_appcast hash"
  validate_sha256_value \
    "$expected_generate_keys_sha256" \
    "generate_keys hash"
  validate_sha256_value \
    "$expected_sign_update_sha256" \
    "sign_update hash"
  if [ "$expected_sparkle_tools_archive_sha256" != "$EXPECTED_SPARKLE_TOOLS_ARCHIVE_SHA256" ]; then
    echo "error: release manifest was not built with the pinned Sparkle tools archive" >&2
    return 1
  fi

  release_status="$(
    git -C "$ROOT_DIR" status \
      --porcelain \
      --untracked-files=all \
      -- \
      . \
      ':(exclude)Marketing/**'
  )"
  if [ -n "$release_status" ]; then
    echo "error: the release source tree must remain clean and committed" >&2
    return 1
  fi
  origin_fetch_url="$(git -C "$ROOT_DIR" remote get-url origin)"
  origin_push_url="$(git -C "$ROOT_DIR" remote get-url --push origin)"
  validate_origin_url "$origin_fetch_url" "origin fetch URL"
  validate_origin_url "$origin_push_url" "origin push URL"
  gh auth status -h github.com >/dev/null
  recover_pending_publication "$tag" "$commit_sha"
  prepare_verified_sparkle_tools "$TEMP_DIR"
  if [ "$SPARKLE_TOOLS_ARCHIVE_SHA256" != "$expected_sparkle_tools_archive_sha256" ] ||
    [ "$GENERATE_APPCAST_SHA256" != "$expected_generate_appcast_sha256" ] ||
    [ "$GENERATE_KEYS_SHA256" != "$expected_generate_keys_sha256" ] ||
    [ "$SIGN_UPDATE_SHA256" != "$expected_sign_update_sha256" ]; then
    echo "error: verified Sparkle release tools differ from the immutable asset manifest" >&2
    return 1
  fi
  current_commit="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  if [ "$current_commit" != "$commit_sha" ]; then
    echo "error: current commit differs from the verified release candidate" >&2
    return 1
  fi
  local_tag_commit="$(git -C "$ROOT_DIR" rev-list -n 1 "$tag" 2>/dev/null || true)"
  if [ "$local_tag_commit" != "$commit_sha" ]; then
    echo "error: local tag $tag must point to $commit_sha" >&2
    return 1
  fi
  remote_tag_commit="$(
    git -C "$ROOT_DIR" ls-remote origin "refs/tags/$tag^{}" |
      /usr/bin/awk 'NR == 1 { print $1 }'
  )"
  if [ -z "$remote_tag_commit" ]; then
    remote_tag_commit="$(
      git -C "$ROOT_DIR" ls-remote origin "refs/tags/$tag" |
        /usr/bin/awk 'NR == 1 { print $1 }'
    )"
  fi
  if [ "$remote_tag_commit" != "$commit_sha" ]; then
    echo "error: remote tag $tag must point to $commit_sha" >&2
    return 1
  fi

  github_api_error_file="$TEMP_DIR/github-api-error"
  target_release_file="$TEMP_DIR/target-release.json"
  if github_api_json_or_404 \
    "/repos/$GH_REPOSITORY/releases/tags/$tag" \
    "$target_release_file" \
    "$github_api_error_file"; then
    echo "error: GitHub Release $tag already exists" >&2
    return 1
  else
    api_status="$?"
    if [ "$api_status" != "4" ]; then
      return "$api_status"
    fi
  fi

  latest_release_file="$TEMP_DIR/latest-release.json"
  latest_tag=""
  if github_api_json_or_404 \
    "/repos/$GH_REPOSITORY/releases/latest" \
    "$latest_release_file" \
    "$github_api_error_file"; then
    latest_release_json="$(<"$latest_release_file")"
    latest_tag="$(
      /usr/bin/python3 -c '
import json
import sys

print(json.load(sys.stdin)["tag_name"])
' <<<"$latest_release_json"
    )"
  else
    api_status="$?"
    if [ "$api_status" != "4" ]; then
      return "$api_status"
    fi
  fi
  if [ -n "$latest_tag" ]; then
    latest_has_appcast="$(
      /usr/bin/python3 -c '
import json
import sys

release = json.load(sys.stdin)
print(
    "true"
    if any(asset["name"] == "appcast.xml" for asset in release["assets"])
    else "false"
)
' <<<"$latest_release_json"
    )"
    if [ "$latest_has_appcast" = "true" ]; then
      /bin/mkdir "$TEMP_DIR/latest"
      gh release download "$latest_tag" \
        --repo "$GH_REPOSITORY" \
        --pattern appcast.xml \
        --dir "$TEMP_DIR/latest"
      latest_appcast="$TEMP_DIR/latest/appcast.xml"
      /usr/bin/xmllint --noout "$latest_appcast"
      "$SIGN_UPDATE" \
        --account "$SPARKLE_KEY_ACCOUNT" \
        --verify \
        "$latest_appcast"
      latest_build="$(
        /usr/bin/xmllint \
          --xpath \
          'string(//*[local-name()="item"]/*[local-name()="version"])' \
          "$latest_appcast"
      )"
      case "$latest_build" in
        "" | *[!0-9]*)
          echo "error: latest appcast contains an unsupported build version" >&2
          return 1
          ;;
      esac
      if [ "$build_version" -le "$latest_build" ]; then
        echo "error: build $build_version must be newer than published build $latest_build" >&2
        return 1
      fi
    else
      if [ "${SITRIGHT_BOOTSTRAP_CONFIRMATION:-}" != "$tag" ]; then
        echo "error: latest release has no appcast; confirm the one-time updater bootstrap with SITRIGHT_BOOTSTRAP_CONFIRMATION=$tag" >&2
        return 1
      fi
      if [ "${SITRIGHT_SPARKLE_KEY_BACKUP_CONFIRMATION:-}" != "$tag" ]; then
        echo "error: confirm the verified offline Sparkle key backup with SITRIGHT_SPARKLE_KEY_BACKUP_CONFIRMATION=$tag" >&2
        return 1
      fi
    fi
  else
    if [ "${SITRIGHT_BOOTSTRAP_CONFIRMATION:-}" != "$tag" ]; then
      echo "error: confirm the one-time updater bootstrap with SITRIGHT_BOOTSTRAP_CONFIRMATION=$tag" >&2
      return 1
    fi
    if [ "${SITRIGHT_SPARKLE_KEY_BACKUP_CONFIRMATION:-}" != "$tag" ]; then
      echo "error: confirm the verified offline Sparkle key backup with SITRIGHT_SPARKLE_KEY_BACKUP_CONFIRMATION=$tag" >&2
      return 1
    fi
  fi

  verify_prepared_assets \
    "$release_dir" \
    "$tag" \
    "$version" \
    "$build_version" \
    "$dmg_name" \
    "$zip_name" \
    "$appcast_name" \
    "$checksums_name"

  gh release create "$tag" \
    "$release_dir/$dmg_name" \
    "$release_dir/$zip_name" \
    "$release_dir/$appcast_name" \
    "$release_dir/$checksums_name" \
    --repo "$GH_REPOSITORY" \
    --draft \
    --verify-tag \
    --title "SitRight $version ($build_version)" \
    --notes-file "$notes_file"

  draft_release_json="$(
    gh release view "$tag" \
      --repo "$GH_REPOSITORY" \
      --json tagName,isDraft,isPrerelease,assets
  )"
  verify_release_json \
    "$draft_release_json" \
    true \
    "$tag" \
    "$dmg_name" \
    "$zip_name" \
    "$appcast_name" \
    "$checksums_name"

  remote_asset_dir="$TEMP_DIR/uploaded-assets"
  /bin/mkdir "$remote_asset_dir"
  gh release download "$tag" \
    --repo "$GH_REPOSITORY" \
    --dir "$remote_asset_dir"
  for asset in "$dmg_name" "$zip_name" "$appcast_name" "$checksums_name"; do
    if ! /usr/bin/cmp -s \
      "$release_dir/$asset" \
      "$remote_asset_dir/$asset"; then
      echo "error: uploaded draft asset differs from the verified local asset: $asset" >&2
      return 1
    fi
  done

  final_release_status="$(
    git -C "$ROOT_DIR" status \
      --porcelain \
      --untracked-files=all \
      -- \
      . \
      ':(exclude)Marketing/**'
  )"
  if [ -n "$final_release_status" ] ||
    [ "$(git -C "$ROOT_DIR" rev-parse HEAD)" != "$commit_sha" ]; then
    echo "error: source tree changed before publishing the verified Draft" >&2
    return 1
  fi
  remote_tag_commit_after="$(
    git -C "$ROOT_DIR" ls-remote origin "refs/tags/$tag^{}" |
      /usr/bin/awk 'NR == 1 { print $1 }'
  )"
  if [ -z "$remote_tag_commit_after" ]; then
    remote_tag_commit_after="$(
      git -C "$ROOT_DIR" ls-remote origin "refs/tags/$tag" |
        /usr/bin/awk 'NR == 1 { print $1 }'
    )"
  fi
  if [ "$remote_tag_commit_after" != "$commit_sha" ]; then
    echo "error: remote tag changed before Draft publication" >&2
    return 1
  fi

  write_publication_state "$tag" "$commit_sha"
  PUBLICATION_TAG="$tag"
  PUBLICATION_IN_PROGRESS=1
  gh release edit "$tag" \
    --repo "$GH_REPOSITORY" \
    --draft=false

  release_json="$(
    gh release view "$tag" \
      --repo "$GH_REPOSITORY" \
      --json tagName,isDraft,isPrerelease,assets
  )"
  verify_release_json \
    "$release_json" \
    false \
    "$tag" \
    "$dmg_name" \
    "$zip_name" \
    "$appcast_name" \
    "$checksums_name"
  remote_tag_commit_after="$(
    git -C "$ROOT_DIR" ls-remote origin "refs/tags/$tag^{}" |
      /usr/bin/awk 'NR == 1 { print $1 }'
  )"
  if [ -z "$remote_tag_commit_after" ]; then
    remote_tag_commit_after="$(
      git -C "$ROOT_DIR" ls-remote origin "refs/tags/$tag" |
        /usr/bin/awk 'NR == 1 { print $1 }'
    )"
  fi
  if [ "$remote_tag_commit_after" != "$commit_sha" ]; then
    echo "error: remote tag changed during Release publication" >&2
    return 1
  fi
  latest_after_publish_json="$(
    gh api \
      --hostname github.com \
      "/repos/$GH_REPOSITORY/releases/latest"
  )"
  if [ "$(
    /usr/bin/python3 -c '
import json
import sys
print(json.load(sys.stdin)["tag_name"])
' <<<"$latest_after_publish_json"
  )" != "$tag" ]; then
    echo "error: published Release is not the repository latest Release" >&2
    return 1
  fi
  PUBLICATION_IN_PROGRESS=0
  PUBLICATION_TAG=""
  clear_publication_state

  echo "Published and verified GitHub Release $tag"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
