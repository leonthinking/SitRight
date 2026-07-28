#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="${TMPDIR:-/private/tmp}/SitRight.build.lock"
if [ "${SITRIGHT_BUILD_LOCK_HELD:-0}" != "1" ]; then
  export SITRIGHT_BUILD_LOCK_HELD=1
  exec /usr/bin/lockf -k -t "${SITRIGHT_BUILD_LOCK_TIMEOUT:-60}" "$LOCK_FILE" "$0" "$@"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="$(mktemp -d "${TMPDIR:-/private/tmp}/SitRightDerivedData.XXXXXX")"
PRODUCTS_PATH="$DERIVED_DATA_PATH/Build/Products/Release"
APP_PATH="${SITRIGHT_OUTPUT_APP_PATH:-$ROOT_DIR/build/SitRight.app}"
INSTALL_APP_PATH="/Applications/SitRight.app"
STAGING_DIR="$(mktemp -d "$DERIVED_DATA_PATH/Signed.XXXXXX")"
STAGED_APP_PATH="$STAGING_DIR/SitRight.app"
WIDGET_PATH="$STAGED_APP_PATH/Contents/PlugIns/SitRightWidgetExtension.appex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
APP_GROUP_IDENTIFIER="973KFG9CL9.com.leon.SitRight"
EXPECTED_TEAM_IDENTIFIER="${APP_GROUP_IDENTIFIER%%.*}"
WIDGET_BUNDLE_IDENTIFIER="com.leon.SitRight.SitRightWidgetExtension"
SITRIGHT_LICENSE_SOURCE="$ROOT_DIR/Sources/Resources/SitRight-License.txt"
THIRD_PARTY_NOTICES_SOURCE="$ROOT_DIR/Sources/Resources/Third-Party-Notices.txt"
BUILD_OUTPUT_STAGING_DIR=""
BUILD_OUTPUT_TARGET_APP=""
BUILD_OUTPUT_PREVIOUS_APP=""
BUILD_OUTPUT_REPLACEMENT_STARTED=0
BUILD_OUTPUT_HAD_PREVIOUS=0
BUILD_OUTPUT_COMMITTED=0
INSTALL_TRANSACTION_DIR="$(dirname "$INSTALL_APP_PATH")/.SitRightInstallTransaction"
INSTALL_TRANSACTION_ACTIVE=0

cleanup() {
  local exit_status="$?"

  trap - EXIT HUP INT TERM
  if [ "$INSTALL_TRANSACTION_ACTIVE" = "1" ] &&
    ! rollback_installation_transaction; then
    exit_status=1
  fi
  if [ "$BUILD_OUTPUT_REPLACEMENT_STARTED" = "1" ] &&
    [ "$BUILD_OUTPUT_COMMITTED" != "1" ]; then
    if [ "$BUILD_OUTPUT_HAD_PREVIOUS" = "1" ] &&
      [ -n "$BUILD_OUTPUT_PREVIOUS_APP" ] &&
      [ -e "$BUILD_OUTPUT_PREVIOUS_APP" ]; then
      rm -rf "$BUILD_OUTPUT_TARGET_APP"
      if ! mv "$BUILD_OUTPUT_PREVIOUS_APP" "$BUILD_OUTPUT_TARGET_APP"; then
        echo "Failed to restore the previous build output; preserved $BUILD_OUTPUT_STAGING_DIR" >&2
        BUILD_OUTPUT_STAGING_DIR=""
        exit_status=1
      fi
    elif [ "$BUILD_OUTPUT_HAD_PREVIOUS" != "1" ] &&
      [ -n "$BUILD_OUTPUT_TARGET_APP" ]; then
      rm -rf "$BUILD_OUTPUT_TARGET_APP"
    fi
  fi
  if [ -n "$BUILD_OUTPUT_STAGING_DIR" ]; then
    rm -rf "$BUILD_OUTPUT_STAGING_DIR"
  fi
  if [ "${SITRIGHT_KEEP_DERIVED_DATA:-0}" != "1" ]; then
    rm -rf "$DERIVED_DATA_PATH"
  fi

  exit "$exit_status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

clear_disallowed_xattrs() {
  local target="$1"
  [ -e "$target" ] || return 0

  while IFS= read -r -d '' item; do
    xattr -d com.apple.FinderInfo "$item" 2>/dev/null || true
    xattr -d 'com.apple.fileprovider.fpfs#P' "$item" 2>/dev/null || true
  done < <(find "$target" -xattr -print0)
}

clear_root_disallowed_xattrs() {
  local target="$1"
  [ -e "$target" ] || return 0

  xattr -d com.apple.FinderInfo "$target" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$target" 2>/dev/null || true
}

unregister_transient_app() {
  local app_path="$1"
  local appex_path="$app_path/Contents/PlugIns/SitRightWidgetExtension.appex"

  [ -e "$appex_path" ] && /usr/bin/pluginkit -r "$appex_path" 2>/dev/null || true
  [ -e "$app_path" ] && "$LSREGISTER" -u "$app_path" 2>/dev/null || true
}

validate_entitlements_xml() {
  local entitlements="$1"
  local label="$2"
  local allow_debugging="${3:-0}"
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
    echo "$label is missing App Group entitlement: $APP_GROUP_IDENTIFIER" >&2
    return 1
  fi

  debug_allowed="$(
    /usr/bin/plutil \
      -extract "com\\.apple\\.security\\.get-task-allow" \
      raw \
      -o - \
      - <<<"$entitlements" 2>/dev/null || true
  )"
  if [ "$debug_allowed" = "true" ] && [ "$allow_debugging" != "1" ]; then
    echo "$label contains the debugging entitlement com.apple.security.get-task-allow" >&2
    return 1
  fi
}

verify_app_group_entitlement() {
  local target="$1"
  local label="$2"
  local allow_debugging="${3:-0}"
  local entitlements

  entitlements="$(/usr/bin/codesign -d --entitlements :- "$target" 2>/dev/null)" || return 1
  validate_entitlements_xml "$entitlements" "$label" "$allow_debugging"
}

team_identifier_for() {
  local target="$1"

  /usr/bin/codesign -dv "$target" 2>&1 |
    /usr/bin/sed -n 's/^TeamIdentifier=//p' |
    /usr/bin/head -1
}

verify_app_group_team_identifier() {
  local target="$1"
  local label="$2"
  local team_identifier

  team_identifier="$(team_identifier_for "$target")"
  if [ "$team_identifier" != "$EXPECTED_TEAM_IDENTIFIER" ]; then
    echo "$label cannot access App Group $APP_GROUP_IDENTIFIER: expected TeamIdentifier=$EXPECTED_TEAM_IDENTIFIER, got ${team_identifier:-not-set}" >&2
    return 1
  fi
}

verify_expected_team_identifier() {
  local target="$1"
  local label="$2"
  local team_identifier

  team_identifier="$(team_identifier_for "$target")"
  if [ "$team_identifier" != "$EXPECTED_TEAM_IDENTIFIER" ]; then
    echo "$label requires TeamIdentifier=$EXPECTED_TEAM_IDENTIFIER, got ${team_identifier:-not-set}" >&2
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
    echo "$label contains the debugging entitlement com.apple.security.get-task-allow" >&2
    return 1
  fi
}

verify_sparkle_components() {
  local app_path="$1"
  local require_expected_team="${2:-0}"
  local framework_path="$app_path/Contents/Frameworks/Sparkle.framework"
  local framework_version="$framework_path/Versions/Current"
  local target
  local label

  if [ ! -d "$framework_path" ]; then
    echo "Sparkle.framework is missing: $framework_path" >&2
    return 1
  fi

  while IFS='|' read -r target label; do
    if [ ! -e "$target" ]; then
      echo "$label is missing: $target" >&2
      return 1
    fi
    /usr/bin/codesign --verify --strict "$target" || return 1
    verify_no_debug_entitlement "$target" "$label" || return 1
    if [ "$require_expected_team" = "1" ]; then
      verify_expected_team_identifier "$target" "$label" || return 1
    fi
  done <<EOF
$framework_version/XPCServices/Downloader.xpc|Sparkle Downloader.xpc
$framework_version/XPCServices/Installer.xpc|Sparkle Installer.xpc
$framework_version/Updater.app|Sparkle Updater.app
$framework_version/Autoupdate|Sparkle Autoupdate
$framework_path|Sparkle.framework
EOF
}

verify_legal_resources() {
  local app_path="$1"
  local label="$2"
  local source_path
  local resource_name
  local bundled_path

  while IFS='|' read -r source_path resource_name; do
    bundled_path="$app_path/Contents/Resources/$resource_name"
    if [ ! -f "$source_path" ] || [ ! -f "$bundled_path" ]; then
      echo "$label is missing required legal resource: $resource_name" >&2
      return 1
    fi
    if ! /usr/bin/cmp -s "$source_path" "$bundled_path"; then
      echo "$label legal resource differs from source: $resource_name" >&2
      return 1
    fi
  done <<EOF
$SITRIGHT_LICENSE_SOURCE|SitRight-License.txt
$THIRD_PARTY_NOTICES_SOURCE|Third-Party-Notices.txt
EOF
}

sign_sparkle_components() {
  local app_path="$1"
  local sign_identity="$2"
  local framework_path="$app_path/Contents/Frameworks/Sparkle.framework"
  local framework_version="$framework_path/Versions/Current"
  local downloader="$framework_version/XPCServices/Downloader.xpc"
  local installer="$framework_version/XPCServices/Installer.xpc"
  local autoupdate="$framework_version/Autoupdate"
  local updater="$framework_version/Updater.app"
  local component

  for component in \
    "$downloader" \
    "$installer" \
    "$autoupdate" \
    "$updater" \
    "$framework_path"; do
    if [ ! -e "$component" ]; then
      echo "Cannot sign missing Sparkle component: $component" >&2
      return 1
    fi
  done

  /usr/bin/codesign \
    --force \
    --sign "$sign_identity" \
    --options runtime \
    --preserve-metadata=entitlements \
    --generate-entitlement-der \
    "$downloader" || return 1
  /usr/bin/codesign \
    --force \
    --sign "$sign_identity" \
    --options runtime \
    --generate-entitlement-der \
    "$installer" || return 1
  /usr/bin/codesign \
    --force \
    --sign "$sign_identity" \
    --options runtime \
    --generate-entitlement-der \
    "$autoupdate" || return 1
  /usr/bin/codesign \
    --force \
    --sign "$sign_identity" \
    --options runtime \
    --generate-entitlement-der \
    "$updater" || return 1
  /usr/bin/codesign \
    --force \
    --sign "$sign_identity" \
    --options runtime \
    --generate-entitlement-der \
    "$framework_path"
}

verify_installable_app() {
  local app_path="$1"
  local label="$2"
  local widget_path="$app_path/Contents/PlugIns/SitRightWidgetExtension.appex"

  verify_app_group_entitlement "$app_path" "$label SitRight.app" || return 1
  verify_app_group_entitlement "$widget_path" "$label SitRightWidgetExtension.appex" || return 1
  verify_app_group_team_identifier "$app_path" "$label SitRight.app" || return 1
  verify_app_group_team_identifier "$widget_path" "$label SitRightWidgetExtension.appex" || return 1
  verify_legal_resources "$app_path" "$label SitRight.app" || return 1
  verify_sparkle_components "$app_path" 1 || return 1
  /usr/bin/codesign --verify --strict "$widget_path" || return 1
  /usr/bin/codesign --verify --strict --deep "$app_path" || return 1
}

prepare_install_candidate() {
  local source_app="$1"
  local candidate_app="$2"

  ditto --norsrc "$source_app" "$candidate_app" || return 1
  xattr -cr "$candidate_app" || return 1
  clear_disallowed_xattrs "$candidate_app"
  clear_root_disallowed_xattrs "$candidate_app"
  verify_installable_app "$candidate_app" "Candidate" || return 1
}

register_installed_app() {
  local install_app="$1"
  local install_widget="$install_app/Contents/PlugIns/SitRightWidgetExtension.appex"
  local attempt
  local registration
  local registered_path_count
  local expected_path_count

  /usr/bin/pluginkit -a "$install_widget" || return 1
  "$LSREGISTER" -f -R -trusted "$install_app" || return 1

  for attempt in 1 2 3 4 5; do
    registration="$(/usr/bin/pluginkit -m -A -v -i "$WIDGET_BUNDLE_IDENTIFIER" 2>/dev/null || true)"
    registered_path_count="$(/usr/bin/grep -Ec '/.*\.appex$' <<<"$registration" || true)"
    expected_path_count="$(/usr/bin/grep -Fc "$install_widget" <<<"$registration" || true)"
    if [ "$registered_path_count" = "1" ] && [ "$expected_path_count" = "1" ]; then
      return 0
    fi
    /bin/sleep 1
  done

  echo "Widget registration did not resolve uniquely to $install_widget" >&2
  return 1
}

write_install_transaction_state() {
  local state="$1"
  local next_state="$INSTALL_TRANSACTION_DIR/state.next"

  /usr/bin/printf '%s\n' "$state" >"$next_state"
  mv "$next_state" "$INSTALL_TRANSACTION_DIR/state"
}

rollback_installation_transaction() {
  local state
  local previous_app="$INSTALL_TRANSACTION_DIR/PreviousSitRight.app"
  local restored_app="$INSTALL_TRANSACTION_DIR/RestoredSitRight.app"
  local had_previous=0

  [ -d "$INSTALL_TRANSACTION_DIR" ] || {
    INSTALL_TRANSACTION_ACTIVE=0
    return 0
  }

  state="$(/bin/cat "$INSTALL_TRANSACTION_DIR/state" 2>/dev/null || true)"
  case "$state" in
    "" | prepared | committed | rolled-back)
      rm -rf "$INSTALL_TRANSACTION_DIR"
      INSTALL_TRANSACTION_ACTIVE=0
      return 0
      ;;
    replacing | old-preserved | installed)
      ;;
    *)
      echo "Unknown installation transaction state '$state'; preserving $INSTALL_TRANSACTION_DIR" >&2
      return 1
      ;;
  esac

  if [ -e "$INSTALL_TRANSACTION_DIR/had-previous-app" ]; then
    had_previous=1
  fi

  if [ "$had_previous" = "1" ] && [ -e "$previous_app" ]; then
    rm -rf "$restored_app"
    ditto --norsrc "$previous_app" "$restored_app" || return 1
    unregister_transient_app "$INSTALL_APP_PATH"
    rm -rf "$INSTALL_APP_PATH"
    mv "$restored_app" "$INSTALL_APP_PATH" || return 1
    register_installed_app "$INSTALL_APP_PATH" || return 1
  elif [ "$had_previous" = "1" ] && [ "$state" = "replacing" ] &&
    [ -e "$INSTALL_APP_PATH" ]; then
    register_installed_app "$INSTALL_APP_PATH" || return 1
  elif [ "$had_previous" = "1" ]; then
    echo "Previous SitRight installation is missing; preserving $INSTALL_TRANSACTION_DIR" >&2
    return 1
  else
    unregister_transient_app "$INSTALL_APP_PATH"
    rm -rf "$INSTALL_APP_PATH"
  fi

  write_install_transaction_state "rolled-back"
  rm -rf "$INSTALL_TRANSACTION_DIR"
  INSTALL_TRANSACTION_ACTIVE=0
}

recover_interrupted_installation() {
  if [ -d "$INSTALL_TRANSACTION_DIR" ]; then
    echo "Recovering interrupted SitRight installation" >&2
    INSTALL_TRANSACTION_ACTIVE=1
    rollback_installation_transaction
  fi
}

verify_release_executable() {
  local target="$1"
  local label="$2"
  local file_description
  local load_commands

  if [ ! -f "$target" ]; then
    echo "$label executable is missing: $target" >&2
    exit 1
  fi

  file_description="$(/usr/bin/file -b "$target")"
  if [[ "$file_description" != *"Mach-O"* ]]; then
    echo "$label executable is not a Mach-O binary: $file_description" >&2
    exit 1
  fi

  load_commands="$(/usr/bin/otool -l "$target")"
  if /usr/bin/grep -Eq '__llvm_cov|__llvm_prf|__LLVM_COV' <<<"$load_commands"; then
    echo "$label executable contains LLVM coverage or profiling sections" >&2
    exit 1
  fi
}

verify_build_output_candidate() {
  local app_path="$1"
  local widget_path="$app_path/Contents/PlugIns/SitRightWidgetExtension.appex"
  local app_executable="$app_path/Contents/MacOS/SitRight"
  local widget_executable="$widget_path/Contents/MacOS/SitRightWidgetExtension"
  local app_architectures
  local widget_architectures
  local sparkle_requires_expected_team=0

  verify_legal_resources "$app_path" "Build output SitRight.app" || return 1
  verify_app_group_entitlement "$app_path" "Build output SitRight.app" 1 || return 1
  verify_app_group_entitlement "$widget_path" "Build output SitRightWidgetExtension.appex" 1 || return 1
  if [ -n "$SIGN_IDENTITY" ]; then
    sparkle_requires_expected_team=1
  fi
  verify_sparkle_components "$app_path" "$sparkle_requires_expected_team" || return 1
  if [ -n "$SIGN_IDENTITY" ]; then
    /usr/bin/codesign --verify --strict "$widget_path" || return 1
    /usr/bin/codesign --verify --strict --deep "$app_path" || return 1
  fi
  verify_release_executable "$app_executable" "Build output SitRight.app"
  verify_release_executable "$widget_executable" "Build output SitRightWidgetExtension.appex"
  app_architectures="$(/usr/bin/lipo -archs "$app_executable")"
  widget_architectures="$(/usr/bin/lipo -archs "$widget_executable")"
  if [ "$app_architectures" != "$widget_architectures" ]; then
    echo "Build output App and Widget architectures differ: app=$app_architectures widget=$widget_architectures" >&2
    return 1
  fi
}

publish_built_app() {
  local source_app="$1"
  local target_app="$2"
  local target_parent
  local candidate_app

  case "$target_app" in
    /*.app)
      ;;
    *)
      echo "Build output must be an absolute .app path: $target_app" >&2
      return 1
      ;;
  esac

  target_parent="$(dirname "$target_app")"
  mkdir -p "$target_parent"
  BUILD_OUTPUT_STAGING_DIR="$(mktemp -d "$target_parent/.SitRightBuildOutput.XXXXXX")"
  candidate_app="$BUILD_OUTPUT_STAGING_DIR/SitRight.app"
  BUILD_OUTPUT_TARGET_APP="$target_app"
  BUILD_OUTPUT_PREVIOUS_APP="$BUILD_OUTPUT_STAGING_DIR/PreviousSitRight.app"

  ditto --norsrc "$source_app" "$candidate_app" || return 1
  verify_build_output_candidate "$candidate_app" || return 1

  if [ -e "$target_app" ]; then
    BUILD_OUTPUT_HAD_PREVIOUS=1
  fi
  BUILD_OUTPUT_REPLACEMENT_STARTED=1
  if [ "$BUILD_OUTPUT_HAD_PREVIOUS" = "1" ]; then
    mv "$target_app" "$BUILD_OUTPUT_PREVIOUS_APP" || return 1
  fi
  mv "$candidate_app" "$target_app" || return 1
  BUILD_OUTPUT_COMMITTED=1

  rm -rf "$BUILD_OUTPUT_PREVIOUS_APP" "$BUILD_OUTPUT_STAGING_DIR"
  BUILD_OUTPUT_STAGING_DIR=""
}

install_to_applications() {
  local source_app="$1"
  local install_app="$2"
  local candidate_app
  local previous_app

  # Validate the source before stopping or replacing the working installation.
  # An ad-hoc signature may contain the App Group entitlement string while the
  # OS still rejects the group because the signature has no TeamIdentifier.
  verify_installable_app "$source_app" "Source" || return 1

  recover_interrupted_installation
  mkdir "$INSTALL_TRANSACTION_DIR"
  INSTALL_TRANSACTION_ACTIVE=1
  candidate_app="$INSTALL_TRANSACTION_DIR/SitRight.app"
  previous_app="$INSTALL_TRANSACTION_DIR/PreviousSitRight.app"

  if ! prepare_install_candidate "$source_app" "$candidate_app"; then
    echo "Failed to prepare a verified SitRight installation candidate" >&2
    return 1
  fi
  write_install_transaction_state "prepared"
  if [ -e "$install_app" ]; then
    /usr/bin/touch "$INSTALL_TRANSACTION_DIR/had-previous-app"
  fi
  write_install_transaction_state "replacing"

  unregister_transient_app "$source_app"
  /usr/bin/pkill -x SitRight 2>/dev/null || true
  unregister_transient_app "$install_app"

  if [ -e "$install_app" ]; then
    mv "$install_app" "$previous_app" || return 1
  fi
  write_install_transaction_state "old-preserved"

  mv "$candidate_app" "$install_app" || return 1
  write_install_transaction_state "installed"
  if ! verify_installable_app "$install_app" "Installed" ||
    ! register_installed_app "$install_app"; then
    echo "SitRight installation failed; restoring the previous installation" >&2
    if ! rollback_installation_transaction; then
      echo "Automatic rollback failed; preserved installation files in $INSTALL_TRANSACTION_DIR" >&2
      return 1
    fi
    return 1
  fi

  write_install_transaction_state "committed"
  rm -rf "$INSTALL_TRANSACTION_DIR"
  INSTALL_TRANSACTION_ACTIVE=0
}

cd "$ROOT_DIR"

if [ "${SITRIGHT_INSTALL_TO_APPLICATIONS:-0}" = "1" ]; then
  recover_interrupted_installation
fi

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/clang-module-cache}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required to build SitRight.app with the WidgetKit extension." >&2
  exit 1
fi

xcodegen generate

xcodebuild \
  -project "$ROOT_DIR/SitRight.xcodeproj" \
  -scheme SitRight \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  ENABLE_CODE_COVERAGE=NO \
  CLANG_COVERAGE_MAPPING=NO \
  build

mkdir -p "$(dirname "$STAGED_APP_PATH")" "$ROOT_DIR/build"
ditto --norsrc "$PRODUCTS_PATH/SitRight.app" "$STAGED_APP_PATH"

xattr -cr "$STAGED_APP_PATH"
clear_disallowed_xattrs "$STAGED_APP_PATH"
verify_legal_resources "$STAGED_APP_PATH" "SitRight.app"

SIGN_IDENTITY="${SITRIGHT_CODE_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)"
fi

if [ -n "$SIGN_IDENTITY" ]; then
  sign_sparkle_components "$STAGED_APP_PATH" "$SIGN_IDENTITY"
  /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --entitlements "$ROOT_DIR/WidgetBundle/SitRightWidgetExtension.entitlements" --generate-entitlement-der "$WIDGET_PATH"
  clear_disallowed_xattrs "$WIDGET_PATH"
  /usr/bin/codesign --verify --strict "$WIDGET_PATH"
  /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --entitlements "$ROOT_DIR/AppBundle/SitRight.entitlements" --generate-entitlement-der "$STAGED_APP_PATH"
fi

clear_root_disallowed_xattrs "$STAGED_APP_PATH"

if [ -n "$SIGN_IDENTITY" ]; then
  verify_sparkle_components "$STAGED_APP_PATH" 1
  /usr/bin/codesign --verify --strict "$WIDGET_PATH"
  /usr/bin/codesign --verify --strict --deep "$STAGED_APP_PATH"
fi

verify_app_group_entitlement "$STAGED_APP_PATH" "SitRight.app" 1
verify_app_group_entitlement "$WIDGET_PATH" "SitRightWidgetExtension.appex" 1

STAGED_APP_TEAM_IDENTIFIER="$(team_identifier_for "$STAGED_APP_PATH")"
STAGED_WIDGET_TEAM_IDENTIFIER="$(team_identifier_for "$WIDGET_PATH")"
if [ "$STAGED_APP_TEAM_IDENTIFIER" = "$EXPECTED_TEAM_IDENTIFIER" ] &&
  [ "$STAGED_WIDGET_TEAM_IDENTIFIER" = "$EXPECTED_TEAM_IDENTIFIER" ]; then
  echo "Verified App Group TeamIdentifier: $EXPECTED_TEAM_IDENTIFIER"
else
  echo "Warning: this build is structurally signed but cannot access App Group $APP_GROUP_IDENTIFIER at runtime (App TeamIdentifier=${STAGED_APP_TEAM_IDENTIFIER:-not-set}, Widget TeamIdentifier=${STAGED_WIDGET_TEAM_IDENTIFIER:-not-set})." >&2
  echo "Use a valid Apple Development signing identity before installing or testing Widget shared data." >&2
fi

APP_EXECUTABLE="$STAGED_APP_PATH/Contents/MacOS/SitRight"
WIDGET_EXECUTABLE="$WIDGET_PATH/Contents/MacOS/SitRightWidgetExtension"
verify_release_executable "$APP_EXECUTABLE" "SitRight.app"
verify_release_executable "$WIDGET_EXECUTABLE" "SitRightWidgetExtension.appex"

APP_ARCHITECTURES="$(/usr/bin/lipo -archs "$APP_EXECUTABLE")"
WIDGET_ARCHITECTURES="$(/usr/bin/lipo -archs "$WIDGET_EXECUTABLE")"
if [ "$APP_ARCHITECTURES" != "$WIDGET_ARCHITECTURES" ]; then
  echo "App and widget architectures differ: app=$APP_ARCHITECTURES widget=$WIDGET_ARCHITECTURES" >&2
  exit 1
fi

publish_built_app "$STAGED_APP_PATH" "$APP_PATH"
verify_legal_resources "$APP_PATH" "Published SitRight.app"

unregister_transient_app "$PRODUCTS_PATH/SitRight.app"

if [ "${SITRIGHT_INSTALL_TO_APPLICATIONS:-0}" = "1" ]; then
  install_to_applications "$APP_PATH" "$INSTALL_APP_PATH"
  echo "$INSTALL_APP_PATH"
fi

if [ "${SITRIGHT_KEEP_DERIVED_DATA:-0}" = "1" ]; then
  echo "Kept DerivedData: $DERIVED_DATA_PATH" >&2
fi

echo "$APP_PATH"
