#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_FILE="${TMPDIR:-/private/tmp}/SitRight.build.lock"
SPARKLE_RELEASE_VERSION="2.9.2"
SPARKLE_TOOLS_ARCHIVE_URL="https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_RELEASE_VERSION/Sparkle-for-Swift-Package-Manager.zip"
EXPECTED_SPARKLE_TOOLS_ARCHIVE_SHA256="b83e37436774556ed055e0244b297ef2c790e0737393bf65bf495fcbba6eed65"
SPARKLE_TOOLS_DIR=""
GENERATE_APPCAST=""
GENERATE_KEYS=""
SIGN_UPDATE=""
SPARKLE_TOOLS_ARCHIVE_SHA256=""
GENERATE_APPCAST_SHA256=""
GENERATE_KEYS_SHA256=""
SIGN_UPDATE_SHA256=""
SPARKLE_KEY_ACCOUNT="${SITRIGHT_SPARKLE_KEY_ACCOUNT:-com.leon.SitRight}"
EXPECTED_FEED_URL="https://github.com/leonthinking/SitRight/releases/latest/download/appcast.xml"
OUTPUT_ROOT="$ROOT_DIR/build/community-releases"
WORK_DIR=""
MOUNT_ROOT=""
MOUNT_POINT=""
ATTACHED_DEVICE=""
CANDIDATE_DIR=""

cleanup() {
  local exit_status="$?"

  trap - EXIT HUP INT TERM
  if [ -n "$ATTACHED_DEVICE" ]; then
    /usr/bin/hdiutil detach "$ATTACHED_DEVICE" >/dev/null 2>&1 || exit_status=1
  fi
  if [ -n "$WORK_DIR" ]; then
    /bin/chmod -R u+w "$WORK_DIR" >/dev/null 2>&1 || true
    rm -rf "$WORK_DIR"
  fi
  if [ -n "$MOUNT_ROOT" ]; then
    rm -rf "$MOUNT_ROOT"
  fi
  if [ -n "$CANDIDATE_DIR" ]; then
    rm -rf "$CANDIDATE_DIR"
  fi
  exit "$exit_status"
}

result_value() {
  local key="$1"
  local result_file="$2"

  /usr/bin/sed -n "s/^$key=//p" "$result_file" | /usr/bin/head -1
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

main() {
  local embedded_public_key
  local keychain_public_key
  local dmg_result
  local dmg_path
  local version
  local build_version
  local architecture
  local tag
  local archive_name
  local archive_path
  local appcast_source_dir
  local dmg_name
  local app_path
  local appcast_path
  local release_notes_file
  local release_notes_name
  local release_notes_sha256
  local release_notes_copy
  local download_prefix
  local enclosure_url
  local enclosure_signature
  local appcast_version
  local embedded_release_notes_count
  local external_release_notes_count
  local source_snapshot
  local candidate_dir
  local final_dir
  local commit_sha
  local start_commit
  local final_commit
  local final_release_status
  local final_release_notes_sha256
  local attach_output
  local release_status
  local sparkle_tools_archive_sha256
  local generate_appcast_sha256
  local generate_keys_sha256
  local sign_update_sha256

  if [ "${SITRIGHT_UPDATE_LOCK_HELD:-0}" != "1" ]; then
    export SITRIGHT_UPDATE_LOCK_HELD=1
    export SITRIGHT_DMG_LOCK_HELD=1
    export SITRIGHT_BUILD_LOCK_HELD=1
    exec /usr/bin/lockf \
      -k \
      -t "${SITRIGHT_BUILD_LOCK_TIMEOUT:-60}" \
      "$LOCK_FILE" \
      "$0" \
      "$@"
  fi

  trap cleanup EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  WORK_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/SitRightUpdate.XXXXXX")"
  prepare_verified_sparkle_tools "$WORK_DIR"
  sparkle_tools_archive_sha256="$SPARKLE_TOOLS_ARCHIVE_SHA256"
  generate_appcast_sha256="$GENERATE_APPCAST_SHA256"
  generate_keys_sha256="$GENERATE_KEYS_SHA256"
  sign_update_sha256="$SIGN_UPDATE_SHA256"

  embedded_public_key="$(
    /usr/bin/plutil \
      -extract SUPublicEDKey \
      raw \
      -o - \
      "$ROOT_DIR/AppBundle/Info.plist"
  )"
  if [ "$embedded_public_key" = "REPLACE_WITH_SPARKLE_ED25519_PUBLIC_KEY" ] ||
    [ -z "$embedded_public_key" ]; then
    echo "error: configure the Sparkle EdDSA public key before packaging an update" >&2
    return 1
  fi
  keychain_public_key="$(
    "$GENERATE_KEYS" --account "$SPARKLE_KEY_ACCOUNT" -p
  )"
  if [ "$keychain_public_key" != "$embedded_public_key" ]; then
    echo "error: the embedded Sparkle public key does not match the local Keychain account" >&2
    return 1
  fi

  tag="${SITRIGHT_RELEASE_TAG:-}"
  if [ -z "$tag" ]; then
    echo "error: SITRIGHT_RELEASE_TAG is required, for example v0.3.0" >&2
    return 1
  fi
  case "$tag" in
    v[0-9]*)
      ;;
    *)
      echo "error: SITRIGHT_RELEASE_TAG must start with v followed by a version" >&2
      return 1
      ;;
  esac
  case "$tag" in
    *[!A-Za-z0-9._-]*)
      echo "error: SITRIGHT_RELEASE_TAG contains unsupported characters" >&2
      return 1
      ;;
  esac
  release_notes_file="${SITRIGHT_RELEASE_NOTES_FILE:-}"
  if [ -z "$release_notes_file" ] || [ ! -f "$release_notes_file" ]; then
    echo "error: SITRIGHT_RELEASE_NOTES_FILE must name reviewed release notes" >&2
    return 1
  fi
  release_notes_file="$(cd "$(/usr/bin/dirname "$release_notes_file")" && pwd)/$(/usr/bin/basename "$release_notes_file")"
  start_commit="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  release_status="$(
    git -C "$ROOT_DIR" status \
      --porcelain \
      --untracked-files=all \
      -- \
      . \
      ':(exclude)Marketing/**'
  )"
  if [ -n "$release_status" ]; then
    echo "error: update assets must be built from a committed source tree" >&2
    return 1
  fi

  MOUNT_ROOT="$(mktemp -d "${TMPDIR:-/private/tmp}/SitRightUpdateMount.XXXXXX")"
  dmg_result="$WORK_DIR/dmg-result"
  release_notes_copy="$WORK_DIR/reviewed-release-notes.md"
  /usr/bin/ditto --norsrc "$release_notes_file" "$release_notes_copy"
  release_notes_sha256="$(
    /usr/bin/shasum -a 256 "$release_notes_copy" |
      /usr/bin/awk '{print $1}'
  )"
  source_snapshot="$WORK_DIR/source"
  /bin/mkdir "$source_snapshot"
  git -C "$ROOT_DIR" archive --format=tar "$start_commit" |
    /usr/bin/tar -xf - -C "$source_snapshot"

  cd "$source_snapshot"
  echo "==> Building and verifying the signed DMG"
  SITRIGHT_DMG_RESULT_PATH="$dmg_result" \
    OPEN_DMG_ON_SUCCESS=0 \
    "$source_snapshot/Scripts/package_dmg.sh"

  dmg_path="$(result_value dmg_path "$dmg_result")"
  version="$(result_value version "$dmg_result")"
  build_version="$(result_value build "$dmg_result")"
  architecture="$(result_value architecture "$dmg_result")"
  if [ "$tag" != "v$version" ]; then
    echo "error: release tag $tag must match app version v$version" >&2
    return 1
  fi
  if [ "$architecture" != "arm64" ]; then
    echo "error: community preview updates currently support arm64 only" >&2
    return 1
  fi

  MOUNT_POINT="$MOUNT_ROOT/SitRight"
  /bin/mkdir "$MOUNT_POINT"
  attach_output="$(
    /usr/bin/hdiutil attach \
      -readonly \
      -nobrowse \
      -mountpoint "$MOUNT_POINT" \
      "$dmg_path"
  )"
  ATTACHED_DEVICE="$(
    /usr/bin/awk '/^\/dev\// { device = $1 } END { print device }' <<<"$attach_output"
  )"
  if [ -z "$ATTACHED_DEVICE" ]; then
    echo "error: failed to mount the verified DMG" >&2
    return 1
  fi

  app_path="$WORK_DIR/SitRight.app"
  /usr/bin/ditto --norsrc "$MOUNT_POINT/SitRight.app" "$app_path"
  /usr/bin/hdiutil detach "$ATTACHED_DEVICE" >/dev/null
  ATTACHED_DEVICE=""

  if [ "$(
    /usr/libexec/PlistBuddy \
      -c "Print :CFBundleIdentifier" \
      "$app_path/Contents/Info.plist"
  )" != "com.leon.SitRight" ]; then
    echo "error: update archive has the wrong bundle identifier" >&2
    return 1
  fi
  if [ "$(
    /usr/libexec/PlistBuddy \
      -c "Print :SUPublicEDKey" \
      "$app_path/Contents/Info.plist"
  )" != "$embedded_public_key" ]; then
    echo "error: built app does not contain the configured Sparkle public key" >&2
    return 1
  fi
  if [ "$(
    /usr/libexec/PlistBuddy \
      -c "Print :SUFeedURL" \
      "$app_path/Contents/Info.plist"
  )" != "$EXPECTED_FEED_URL" ]; then
    echo "error: built app contains an unexpected Sparkle feed URL" >&2
    return 1
  fi

  /bin/mkdir -p "$OUTPUT_ROOT"
  candidate_dir="$(mktemp -d "$OUTPUT_ROOT/.candidate.XXXXXX")"
  CANDIDATE_DIR="$candidate_dir"
  dmg_name="$(/usr/bin/basename "$dmg_path")"
  archive_name="SitRight-$version-build$build_version-$architecture.zip"
  archive_path="$candidate_dir/$archive_name"
  /usr/bin/ditto \
    -c \
    -k \
    --keepParent \
    --norsrc \
    "$app_path" \
    "$archive_path"

  verify_update_zip_contents "$archive_path"

  appcast_source_dir="$WORK_DIR/appcast-source"
  /bin/mkdir "$appcast_source_dir"
  /usr/bin/ditto --norsrc \
    "$archive_path" \
    "$appcast_source_dir/$archive_name"
  release_notes_name="${archive_name%.zip}.md"
  /usr/bin/ditto --norsrc \
    "$release_notes_copy" \
    "$appcast_source_dir/$release_notes_name"
  download_prefix="https://github.com/leonthinking/SitRight/releases/download/$tag/"
  "$GENERATE_APPCAST" \
    --account "$SPARKLE_KEY_ACCOUNT" \
    --download-url-prefix "$download_prefix" \
    --link "https://github.com/leonthinking/SitRight/releases" \
    --embed-release-notes \
    --versions "$build_version" \
    --maximum-deltas 0 \
    --maximum-versions 1 \
    "$appcast_source_dir"

  appcast_path="$appcast_source_dir/appcast.xml"
  /usr/bin/xmllint --noout "$appcast_path"
  "$SIGN_UPDATE" \
    --account "$SPARKLE_KEY_ACCOUNT" \
    --verify \
    "$appcast_path"

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
  appcast_version="$(
    /usr/bin/xmllint \
      --xpath \
      'string(//*[local-name()="item"]/*[local-name()="version"])' \
      "$appcast_path"
  )"
  embedded_release_notes_count="$(
    /usr/bin/xmllint \
      --xpath \
      'count(//*[local-name()="item"]/*[local-name()="description"])' \
      "$appcast_path"
  )"
  external_release_notes_count="$(
    /usr/bin/xmllint \
      --xpath \
      'count(//*[local-name()="item"]/*[local-name()="releaseNotesLink"])' \
      "$appcast_path"
  )"
  if [ "$enclosure_url" != "$download_prefix$archive_name" ] ||
    [ "$appcast_version" != "$build_version" ] ||
    [ "$embedded_release_notes_count" != "1" ] ||
    [ "$external_release_notes_count" != "0" ] ||
    [ -z "$enclosure_signature" ]; then
    echo "error: generated appcast does not match the release asset contract" >&2
    return 1
  fi
  "$SIGN_UPDATE" \
    --account "$SPARKLE_KEY_ACCOUNT" \
    --verify \
    "$archive_path" \
    "$enclosure_signature"
  /usr/bin/ditto --norsrc "$appcast_path" "$candidate_dir/appcast.xml"
  /usr/bin/ditto --norsrc "$dmg_path" "$candidate_dir/$dmg_name"

  (
    cd "$candidate_dir"
    /usr/bin/shasum \
      -a 256 \
      "$dmg_name" \
      "$archive_name" \
      appcast.xml \
      >SHA256SUMS
    /usr/bin/shasum -a 256 -c SHA256SUMS
  )

  final_commit="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  final_release_status="$(
    git -C "$ROOT_DIR" status \
      --porcelain \
      --untracked-files=all \
      -- \
      . \
      ':(exclude)Marketing/**'
  )"
  final_release_notes_sha256="$(
    /usr/bin/shasum -a 256 "$release_notes_file" |
      /usr/bin/awk '{print $1}'
  )"
  if [ "$final_commit" != "$start_commit" ] ||
    [ -n "$final_release_status" ]; then
    echo "error: source tree changed while update assets were being built" >&2
    return 1
  fi
  if [ "$final_release_notes_sha256" != "$release_notes_sha256" ]; then
    echo "error: release notes changed while update assets were being built" >&2
    return 1
  fi
  commit_sha="$start_commit"
  /usr/bin/printf \
    'tag=%s\nversion=%s\nbuild=%s\narchitecture=%s\ncommit=%s\ndmg=%s\nzip=%s\nappcast=appcast.xml\nchecksums=SHA256SUMS\nrelease_notes_sha256=%s\nsparkle_tools_archive_sha256=%s\ngenerate_appcast_sha256=%s\ngenerate_keys_sha256=%s\nsign_update_sha256=%s\n' \
    "$tag" \
    "$version" \
    "$build_version" \
    "$architecture" \
    "$commit_sha" \
    "$dmg_name" \
    "$archive_name" \
    "$release_notes_sha256" \
    "$sparkle_tools_archive_sha256" \
    "$generate_appcast_sha256" \
    "$generate_keys_sha256" \
    "$sign_update_sha256" \
    >"$candidate_dir/RELEASE-MANIFEST"

  final_dir="$OUTPUT_ROOT/$tag-build$build_version"
  if [ -e "$final_dir" ]; then
    if /usr/bin/cmp -s \
      "$candidate_dir/SHA256SUMS" \
      "$final_dir/SHA256SUMS" &&
      /usr/bin/cmp -s \
        "$candidate_dir/RELEASE-MANIFEST" \
        "$final_dir/RELEASE-MANIFEST" &&
      (
        cd "$final_dir"
        /usr/bin/shasum -a 256 -c SHA256SUMS >/dev/null
      ); then
      rm -rf "$candidate_dir"
      CANDIDATE_DIR=""
      echo "Verified existing update assets: $final_dir"
      return 0
    fi
    echo "error: refusing to overwrite different assets in $final_dir" >&2
    return 1
  fi

  /bin/mv "$candidate_dir" "$final_dir"
  CANDIDATE_DIR=""
  echo
  echo "SUCCESS: prepared GitHub community preview assets"
  echo "    directory: $final_dir"
  echo "    tag: $tag"
  echo "    version/build: $version ($build_version)"
  echo "    signing: Sparkle EdDSA account $SPARKLE_KEY_ACCOUNT"
  echo "    publication: not uploaded"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
