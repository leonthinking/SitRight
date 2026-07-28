#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_FILE="${TMPDIR:-/private/tmp}/SitRight.build.lock"
WIDGET_RELATIVE_PATH="Contents/PlugIns/SitRightWidgetExtension.appex"
APP_GROUP_IDENTIFIER="973KFG9CL9.com.leon.SitRight"
EXPECTED_TEAM_IDENTIFIER="${APP_GROUP_IDENTIFIER%%.*}"
EXPECTED_INSTALLER_MACH_SERVICE="com.leon.SitRight-spki"
EXPECTED_STATUS_MACH_SERVICE="com.leon.SitRight-spks"
OUTPUT_DIR="$ROOT_DIR/build"
OUTPUT_TRANSACTION_DIR="$OUTPUT_DIR/.SitRightDMGTransaction"
STAGING_DIR=""
MOUNT_ROOT=""
OUTPUT_STAGING_DIR=""
MOUNT_POINT=""
ATTACHED_DEVICE=""

detach_attached_image() {
  local detach_target="$ATTACHED_DEVICE"

  if [ -z "$detach_target" ] &&
    [ -n "$MOUNT_POINT" ] &&
    /sbin/mount | /usr/bin/grep -Fq " on $MOUNT_POINT ("; then
    detach_target="$MOUNT_POINT"
  fi
  if [ -z "$detach_target" ]; then
    return 0
  fi

  if /usr/bin/hdiutil detach "$detach_target" >/dev/null 2>&1; then
    ATTACHED_DEVICE=""
    MOUNT_POINT=""
    return 0
  fi

  /bin/sleep 1
  if /usr/bin/hdiutil detach "$detach_target" >/dev/null; then
    ATTACHED_DEVICE=""
    MOUNT_POINT=""
    return 0
  fi

  return 1
}

write_transaction_state() {
  local state="$1"
  local next_state="$OUTPUT_TRANSACTION_DIR/state.next"

  /usr/bin/printf '%s\n' "$state" >"$next_state"
  /bin/mv "$next_state" "$OUTPUT_TRANSACTION_DIR/state"
}

transaction_output_name() {
  local metadata_file="$1"
  local output_name

  [ -f "$metadata_file" ] || return 1
  output_name="$(/bin/cat "$metadata_file")"
  case "$output_name" in
    "" | "." | ".." | */*)
      return 1
      ;;
  esac
  /usr/bin/printf '%s\n' "$output_name"
}

rollback_artifact_transaction() {
  local state
  local dmg_name
  local checksum_name
  local final_dmg
  local final_checksum
  local recovery_failed=0

  [ -d "$OUTPUT_TRANSACTION_DIR" ] || return 0
  state="$(/bin/cat "$OUTPUT_TRANSACTION_DIR/state" 2>/dev/null || true)"
  case "$state" in
    "" | prepared | committed | rolled-back)
      rm -rf "$OUTPUT_TRANSACTION_DIR"
      OUTPUT_STAGING_DIR=""
      return 0
      ;;
    publishing | old-preserved | dmg-published)
      ;;
    *)
      echo "error: unknown DMG publication transaction state '$state'; preserving $OUTPUT_TRANSACTION_DIR" >&2
      OUTPUT_STAGING_DIR=""
      return 1
      ;;
  esac

  if ! dmg_name="$(transaction_output_name "$OUTPUT_TRANSACTION_DIR/final-dmg-name")" ||
    ! checksum_name="$(transaction_output_name "$OUTPUT_TRANSACTION_DIR/final-checksum-name")"; then
    echo "error: invalid DMG publication transaction metadata; preserving $OUTPUT_TRANSACTION_DIR" >&2
    OUTPUT_STAGING_DIR=""
    return 1
  fi

  final_dmg="$OUTPUT_DIR/$dmg_name"
  final_checksum="$OUTPUT_DIR/$checksum_name"

  if [ -e "$OUTPUT_TRANSACTION_DIR/had-previous-dmg" ]; then
    if [ -e "$OUTPUT_TRANSACTION_DIR/previous.dmg" ]; then
      /bin/cp -p "$OUTPUT_TRANSACTION_DIR/previous.dmg" "$final_dmg" || recovery_failed=1
    elif [ "$state" != "publishing" ]; then
      recovery_failed=1
    fi
  else
    rm -f "$final_dmg" || recovery_failed=1
  fi

  if [ -e "$OUTPUT_TRANSACTION_DIR/had-previous-checksum" ]; then
    if [ -e "$OUTPUT_TRANSACTION_DIR/previous.dmg.sha256" ]; then
      /bin/cp -p "$OUTPUT_TRANSACTION_DIR/previous.dmg.sha256" "$final_checksum" || recovery_failed=1
    elif [ "$state" != "publishing" ]; then
      recovery_failed=1
    fi
  else
    rm -f "$final_checksum" || recovery_failed=1
  fi

  if [ "$recovery_failed" = "1" ]; then
    echo "error: failed to restore previous DMG outputs; preserving $OUTPUT_TRANSACTION_DIR" >&2
    OUTPUT_STAGING_DIR=""
    return 1
  fi

  write_transaction_state "rolled-back"
  rm -rf "$OUTPUT_TRANSACTION_DIR"
  OUTPUT_STAGING_DIR=""
}

recover_interrupted_publication() {
  if [ -d "$OUTPUT_TRANSACTION_DIR" ]; then
    echo "==> Recovering interrupted DMG publication"
    rollback_artifact_transaction
  fi
}

cleanup() {
  local exit_status="$?"

  trap - EXIT HUP INT TERM
  if ! detach_attached_image; then
    echo "error: failed to detach $ATTACHED_DEVICE; preserving mount root at $MOUNT_ROOT" >&2
    MOUNT_ROOT=""
    if [ "$exit_status" = "0" ]; then
      exit_status=1
    fi
  fi
  if ! rollback_artifact_transaction; then
    exit_status=1
  fi
  if [ -n "$STAGING_DIR" ]; then
    rm -rf "$STAGING_DIR"
  fi
  if [ -n "$MOUNT_ROOT" ]; then
    rm -rf "$MOUNT_ROOT"
  fi

  exit "$exit_status"
}

team_identifier_for() {
  local target="$1"

  /usr/bin/codesign -dv "$target" 2>&1 |
    /usr/bin/sed -n 's/^TeamIdentifier=//p' |
    /usr/bin/head -1
}

validate_entitlements_xml() {
  local entitlements="$1"
  local label="$2"
  local group_index=0
  local group_value
  local expected_group_found=0
  local debug_allowed

  while group_value="$(
    /usr/bin/plutil \
      -extract "com\\.apple\\.security\\.application-groups.$group_index" \
      raw \
      -o - \
      - <<<"$entitlements" 2>/dev/null
  )"; do
    if [ "$group_value" = "$APP_GROUP_IDENTIFIER" ]; then
      expected_group_found=1
    fi
    group_index=$((group_index + 1))
  done

  if [ "$expected_group_found" != "1" ]; then
    echo "error: $label is missing App Group entitlement $APP_GROUP_IDENTIFIER" >&2
    return 1
  fi

  debug_allowed="$(
    /usr/bin/plutil \
      -extract "com\\.apple\\.security\\.get-task-allow" \
      raw \
      -o - \
      - <<<"$entitlements" 2>/dev/null || true
  )"
  if [ "$debug_allowed" = "true" ]; then
    echo "error: $label contains the debugging entitlement com.apple.security.get-task-allow" >&2
    return 1
  fi
}

validate_update_entitlements_xml() {
  local entitlements="$1"
  local label="$2"
  local role="$3"
  local sandbox_enabled
  local group_index=0
  local group_value
  local mach_index=0
  local mach_value
  local installer_service_found=0
  local status_service_found=0

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
    if [ "$group_value" != "$APP_GROUP_IDENTIFIER" ]; then
      echo "error: $label contains an unexpected App Group entitlement" >&2
      return 1
    fi
    group_index=$((group_index + 1))
  done
  if [ "$group_index" != "1" ]; then
    echo "error: $label must contain exactly one App Group entitlement" >&2
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
        echo "error: $label contains an unexpected Mach lookup entitlement" >&2
        return 1
        ;;
    esac
    mach_index=$((mach_index + 1))
  done

  case "$role" in
    app)
      if [ "$mach_index" != "2" ] ||
        [ "$installer_service_found" != "1" ] ||
        [ "$status_service_found" != "1" ]; then
        echo "error: $label must contain the exact Sparkle Mach services" >&2
        return 1
      fi
      ;;
    widget)
      if [ "$mach_index" != "0" ]; then
        echo "error: $label must not contain Sparkle Mach services" >&2
        return 1
      fi
      ;;
    *)
      echo "error: unsupported entitlement validation role: $role" >&2
      return 1
      ;;
  esac
}

verify_app_group_contract() {
  local target="$1"
  local label="$2"
  local role="$3"
  local entitlements
  local team_identifier

  entitlements="$(/usr/bin/codesign -d --entitlements :- "$target" 2>/dev/null)"
  validate_entitlements_xml "$entitlements" "$label"
  validate_update_entitlements_xml "$entitlements" "$label" "$role"

  team_identifier="$(team_identifier_for "$target")"
  if [ "$team_identifier" != "$EXPECTED_TEAM_IDENTIFIER" ]; then
    echo "error: $label requires TeamIdentifier=$EXPECTED_TEAM_IDENTIFIER, got ${team_identifier:-not-set}" >&2
    return 1
  fi
}

verify_expected_team_identifier() {
  local target="$1"
  local label="$2"
  local team_identifier

  team_identifier="$(team_identifier_for "$target")"
  if [ "$team_identifier" != "$EXPECTED_TEAM_IDENTIFIER" ]; then
    echo "error: $label requires TeamIdentifier=$EXPECTED_TEAM_IDENTIFIER, got ${team_identifier:-not-set}" >&2
    return 1
  fi
}

verify_no_debug_entitlement() {
  local target="$1"
  local label="$2"
  local entitlements
  local debug_allowed

  entitlements="$(/usr/bin/codesign -d --entitlements :- "$target" 2>/dev/null)" || return 1
  debug_allowed="$(
    /usr/bin/plutil \
      -extract "com\\.apple\\.security\\.get-task-allow" \
      raw \
      -o - \
      - <<<"$entitlements" 2>/dev/null || true
  )"
  if [ "$debug_allowed" = "true" ]; then
    echo "error: $label contains the debugging entitlement com.apple.security.get-task-allow" >&2
    return 1
  fi
}

verify_sparkle_components() {
  local app_path="$1"
  local framework_path="$app_path/Contents/Frameworks/Sparkle.framework"
  local framework_version="$framework_path/Versions/Current"
  local target
  local label

  if [ ! -d "$framework_path" ]; then
    echo "error: Sparkle.framework is missing: $framework_path" >&2
    return 1
  fi

  while IFS='|' read -r target label; do
    if [ ! -e "$target" ]; then
      echo "error: $label is missing: $target" >&2
      return 1
    fi
    /usr/bin/codesign --verify --strict "$target" || return 1
    verify_expected_team_identifier "$target" "$label" || return 1
    verify_no_debug_entitlement "$target" "$label" || return 1
  done <<EOF
$framework_version/XPCServices/Downloader.xpc|Sparkle Downloader.xpc
$framework_version/XPCServices/Installer.xpc|Sparkle Installer.xpc
$framework_version/Updater.app|Sparkle Updater.app
$framework_version/Autoupdate|Sparkle Autoupdate
$framework_path|Sparkle.framework
EOF
}

verify_packageable_app() {
  local app_path="$1"
  local label="$2"
  local widget_path="$app_path/$WIDGET_RELATIVE_PATH"
  local app_short_version
  local widget_short_version
  local app_build_version
  local widget_build_version

  if [ ! -d "$app_path" ]; then
    echo "error: $label app bundle is missing: $app_path" >&2
    return 1
  fi
  if [ ! -d "$widget_path" ]; then
    echo "error: $label Widget extension is missing: $widget_path" >&2
    return 1
  fi

  /usr/bin/codesign --verify --strict "$widget_path"
  /usr/bin/codesign --verify --strict --deep "$app_path"
  verify_app_group_contract "$app_path" "$label SitRight.app" app
  verify_app_group_contract "$widget_path" "$label SitRightWidgetExtension.appex" widget
  verify_sparkle_components "$app_path"

  app_short_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app_path/Contents/Info.plist")"
  widget_short_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$widget_path/Contents/Info.plist")"
  app_build_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$app_path/Contents/Info.plist")"
  widget_build_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$widget_path/Contents/Info.plist")"

  if [ "$app_short_version" != "$widget_short_version" ] ||
    [ "$app_build_version" != "$widget_build_version" ]; then
    echo "error: $label App/Widget versions differ: App=$app_short_version ($app_build_version), Widget=$widget_short_version ($widget_build_version)" >&2
    return 1
  fi
}

architecture_label_for() {
  local app_path="$1"
  local widget_path="$app_path/$WIDGET_RELATIVE_PATH"
  local app_architectures
  local widget_architectures

  app_architectures="$(/usr/bin/lipo -archs "$app_path/Contents/MacOS/SitRight")"
  widget_architectures="$(/usr/bin/lipo -archs "$widget_path/Contents/MacOS/SitRightWidgetExtension")"
  if [ "$app_architectures" != "$widget_architectures" ]; then
    echo "error: App and Widget architectures differ: App=$app_architectures, Widget=$widget_architectures" >&2
    return 1
  fi

  case "$app_architectures" in
    arm64)
      echo "arm64"
      ;;
    x86_64)
      echo "x86_64"
      ;;
    "arm64 x86_64" | "x86_64 arm64")
      echo "universal"
      ;;
    *)
      echo "error: unsupported packaged architectures: $app_architectures" >&2
      return 1
      ;;
  esac
}

write_tree_manifest() {
  local root="$1"
  local output="$2"
  local item
  local relative_path
  local mode
  local size
  local hash
  local link_target

  : >"$output"
  while IFS= read -r item; do
    relative_path="${item#"$root"/}"
    mode="$(/usr/bin/stat -f '%Lp' "$item")"
    if [ -L "$item" ]; then
      link_target="$(/usr/bin/readlink "$item")"
      /usr/bin/printf \
        'link\t%s\t%s\t%s\n' \
        "$mode" \
        "$relative_path" \
        "$link_target" \
        >>"$output"
    elif [ -f "$item" ]; then
      size="$(/usr/bin/stat -f '%z' "$item")"
      hash="$(/usr/bin/shasum -a 256 "$item" | /usr/bin/awk '{print $1}')"
      /usr/bin/printf \
        'file\t%s\t%s\t%s\t%s\n' \
        "$mode" \
        "$size" \
        "$hash" \
        "$relative_path" \
        >>"$output"
    elif [ -d "$item" ]; then
      /usr/bin/printf \
        'directory\t%s\t%s\n' \
        "$mode" \
        "$relative_path" \
        >>"$output"
    else
      echo "error: unsupported filesystem item in app bundle: $relative_path" >&2
      return 1
    fi
  done < <(
    /usr/bin/find "$root" -xdev -mindepth 1 -print |
      LC_ALL=C /usr/bin/sort
  )
}

publish_artifact_pair() {
  local candidate_dmg="$1"
  local candidate_checksum="$2"
  local final_dmg="$3"
  local final_checksum="$4"
  local previous_dmg="$OUTPUT_STAGING_DIR/previous.dmg"
  local previous_checksum="$OUTPUT_STAGING_DIR/previous.dmg.sha256"

  /usr/bin/printf '%s\n' "$(/usr/bin/basename "$final_dmg")" \
    >"$OUTPUT_STAGING_DIR/final-dmg-name.next"
  /bin/mv \
    "$OUTPUT_STAGING_DIR/final-dmg-name.next" \
    "$OUTPUT_STAGING_DIR/final-dmg-name"
  /usr/bin/printf '%s\n' "$(/usr/bin/basename "$final_checksum")" \
    >"$OUTPUT_STAGING_DIR/final-checksum-name.next"
  /bin/mv \
    "$OUTPUT_STAGING_DIR/final-checksum-name.next" \
    "$OUTPUT_STAGING_DIR/final-checksum-name"
  write_transaction_state "prepared"

  if [ -e "$final_dmg" ]; then
    /usr/bin/touch "$OUTPUT_STAGING_DIR/had-previous-dmg"
  fi
  if [ -e "$final_checksum" ]; then
    /usr/bin/touch "$OUTPUT_STAGING_DIR/had-previous-checksum"
  fi
  write_transaction_state "publishing"

  if [ -e "$final_dmg" ]; then
    /bin/mv "$final_dmg" "$previous_dmg"
  fi
  if [ -e "$final_checksum" ]; then
    /bin/mv "$final_checksum" "$previous_checksum"
  fi
  write_transaction_state "old-preserved"

  /bin/mv "$candidate_dmg" "$final_dmg"
  write_transaction_state "dmg-published"
  /bin/mv "$candidate_checksum" "$final_checksum"
  write_transaction_state "committed"

  rm -rf "$OUTPUT_STAGING_DIR"
  OUTPUT_STAGING_DIR=""
}

main() {
  local attach_output
  local candidate_dmg_path
  local candidate_checksum_path
  local dmg_path
  local checksum_path
  local sha256
  local size
  local signing_authority
  local built_app_path
  local image_staging_dir
  local mounted_entry_count
  local staged_manifest
  local mounted_manifest

  if [ "${SITRIGHT_DMG_LOCK_HELD:-0}" != "1" ]; then
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
  recover_interrupted_publication
  STAGING_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/SitRightDMG.XXXXXX")"
  MOUNT_ROOT="$(mktemp -d "${TMPDIR:-/private/tmp}/SitRightDMGMount.XXXXXX")"
  /bin/mkdir "$STAGING_DIR/build" "$STAGING_DIR/image"
  built_app_path="$STAGING_DIR/build/BuiltSitRight.app"
  image_staging_dir="$STAGING_DIR/image"

  cd "$ROOT_DIR"

  echo "==> Building signed SitRight.app"
  SITRIGHT_OUTPUT_APP_PATH="$built_app_path" \
    SITRIGHT_INSTALL_TO_APPLICATIONS=0 \
    "$ROOT_DIR/Scripts/build_app.sh"

  verify_packageable_app "$built_app_path" "Built"
  ARCHITECTURE_LABEL="$(architecture_label_for "$built_app_path")"
  VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$built_app_path/Contents/Info.plist")"
  BUILD_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$built_app_path/Contents/Info.plist")"
  dmg_path="$OUTPUT_DIR/SitRight-$VERSION-build$BUILD_VERSION-$ARCHITECTURE_LABEL.dmg"
  checksum_path="$dmg_path.sha256"
  STAGED_APP_PATH="$image_staging_dir/SitRight.app"
  OUTPUT_STAGING_DIR="$OUTPUT_TRANSACTION_DIR"
  /bin/mkdir "$OUTPUT_STAGING_DIR"
  candidate_dmg_path="$OUTPUT_STAGING_DIR/candidate.dmg"
  candidate_checksum_path="$OUTPUT_STAGING_DIR/candidate.dmg.sha256"

  echo "==> Staging SitRight.app and Applications shortcut"
  /usr/bin/ditto --norsrc "$built_app_path" "$STAGED_APP_PATH"
  /bin/ln -s /Applications "$image_staging_dir/Applications"
  verify_packageable_app "$STAGED_APP_PATH" "Staged"

  echo "==> Creating candidate DMG for $dmg_path"
  /usr/bin/hdiutil create \
    -volname "SitRight $VERSION" \
    -srcfolder "$image_staging_dir" \
    -format UDZO \
    -fs HFS+ \
    "$candidate_dmg_path" >/dev/null

  echo "==> Verifying and mounting candidate DMG"
  /usr/bin/hdiutil verify "$candidate_dmg_path" >/dev/null
  MOUNT_POINT="$MOUNT_ROOT/SitRight"
  /bin/mkdir -p "$MOUNT_POINT"
  attach_output="$(
    /usr/bin/hdiutil attach \
      -readonly \
      -nobrowse \
      -mountpoint "$MOUNT_POINT" \
      "$candidate_dmg_path"
  )"
  ATTACHED_DEVICE="$(
    /usr/bin/awk '/^\/dev\// { device = $1 } END { print device }' <<<"$attach_output"
  )"
  if [ -z "$ATTACHED_DEVICE" ]; then
    echo "error: hdiutil did not report the attached device" >&2
    return 1
  fi

  if [ ! -L "$MOUNT_POINT/Applications" ] ||
    [ "$(/usr/bin/readlink "$MOUNT_POINT/Applications")" != "/Applications" ]; then
    echo "error: mounted DMG is missing Applications -> /Applications" >&2
    return 1
  fi
  mounted_entry_count="$(
    /usr/bin/find "$MOUNT_POINT" -mindepth 1 -maxdepth 1 -print |
      /usr/bin/wc -l |
      /usr/bin/tr -d ' '
  )"
  if [ "$mounted_entry_count" != "2" ] ||
    [ ! -d "$MOUNT_POINT/SitRight.app" ]; then
    echo "error: mounted DMG must contain only SitRight.app and Applications" >&2
    return 1
  fi
  staged_manifest="$STAGING_DIR/staged-app.manifest"
  mounted_manifest="$STAGING_DIR/mounted-app.manifest"
  write_tree_manifest "$STAGED_APP_PATH" "$staged_manifest"
  write_tree_manifest "$MOUNT_POINT/SitRight.app" "$mounted_manifest"
  /usr/bin/diff -u "$staged_manifest" "$mounted_manifest"
  verify_packageable_app "$MOUNT_POINT/SitRight.app" "Mounted"

  detach_attached_image

  sha256="$(/usr/bin/shasum -a 256 "$candidate_dmg_path" | /usr/bin/awk '{print $1}')"
  /usr/bin/printf \
    '%s  %s\n' \
    "$sha256" \
    "$(/usr/bin/basename "$dmg_path")" \
    >"$candidate_checksum_path"
  publish_artifact_pair \
    "$candidate_dmg_path" \
    "$candidate_checksum_path" \
    "$dmg_path" \
    "$checksum_path"

  if [ -n "${SITRIGHT_DMG_RESULT_PATH:-}" ]; then
    case "$SITRIGHT_DMG_RESULT_PATH" in
      /*)
        ;;
      *)
        echo "error: SITRIGHT_DMG_RESULT_PATH must be absolute" >&2
        return 1
        ;;
    esac
    /usr/bin/printf \
      'dmg_path=%s\nchecksum_path=%s\nversion=%s\nbuild=%s\narchitecture=%s\nsha256=%s\n' \
      "$dmg_path" \
      "$checksum_path" \
      "$VERSION" \
      "$BUILD_VERSION" \
      "$ARCHITECTURE_LABEL" \
      "$sha256" \
      >"$SITRIGHT_DMG_RESULT_PATH.next"
    /bin/mv "$SITRIGHT_DMG_RESULT_PATH.next" "$SITRIGHT_DMG_RESULT_PATH"
  fi

  size="$(/usr/bin/du -h "$dmg_path" | /usr/bin/awk '{print $1}')"
  signing_authority="$(
    /usr/bin/codesign -dv --verbose=4 "$STAGED_APP_PATH" 2>&1 |
      /usr/bin/sed -n 's/^Authority=//p' |
      /usr/bin/head -1
  )"

  echo
  echo "SUCCESS: $dmg_path ($size)"
  echo "    sha256: $sha256"
  echo "    checksum file: $checksum_path"
  echo "    architectures: $ARCHITECTURE_LABEL"
  echo "    signing authority: ${signing_authority:-unknown}"
  echo "    distribution: internal testing only (this script does not notarize or staple)"

  if [ "${OPEN_DMG_ON_SUCCESS:-0}" = "1" ]; then
    echo "==> Opening DMG"
    /usr/bin/open "$dmg_path" || true
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
