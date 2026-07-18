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
APP_PATH="$ROOT_DIR/build/SitRight.app"
INSTALL_APP_PATH="/Applications/SitRight.app"
STAGING_DIR="$(mktemp -d "$DERIVED_DATA_PATH/Signed.XXXXXX")"
STAGED_APP_PATH="$STAGING_DIR/SitRight.app"
WIDGET_PATH="$STAGED_APP_PATH/Contents/PlugIns/SitRightWidgetExtension.appex"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
APP_GROUP_IDENTIFIER="973KFG9CL9.com.leon.SitRight"

cleanup() {
  if [ "${SITRIGHT_KEEP_DERIVED_DATA:-0}" != "1" ]; then
    rm -rf "$DERIVED_DATA_PATH"
  fi
}
trap cleanup EXIT

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

verify_app_group_entitlement() {
  local target="$1"
  local label="$2"
  local entitlements

  if ! entitlements="$(/usr/bin/codesign -d --entitlements - "$target" 2>/dev/null)" ||
    ! /usr/bin/grep -Fq "com.apple.security.application-groups" <<<"$entitlements" ||
    ! /usr/bin/grep -Fq "$APP_GROUP_IDENTIFIER" <<<"$entitlements"; then
    echo "$label is missing App Group entitlement: $APP_GROUP_IDENTIFIER" >&2
    exit 1
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

install_to_applications() {
  local source_app="$1"
  local install_app="$2"
  local install_widget="$install_app/Contents/PlugIns/SitRightWidgetExtension.appex"

  /usr/bin/pkill -x SitRight 2>/dev/null || true
  unregister_transient_app "$install_app"

  rm -rf "$install_app"
  mkdir -p "$(dirname "$install_app")"
  ditto --norsrc "$source_app" "$install_app"
  xattr -cr "$install_app"
  clear_disallowed_xattrs "$install_app"
  clear_root_disallowed_xattrs "$install_app"

  verify_app_group_entitlement "$install_app" "Installed SitRight.app"
  verify_app_group_entitlement "$install_widget" "Installed SitRightWidgetExtension.appex"

  "$LSREGISTER" -f -R -trusted "$install_app" 2>/dev/null || true
}

cd "$ROOT_DIR"

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

rm -rf "$APP_PATH"
mkdir -p "$(dirname "$STAGED_APP_PATH")" "$ROOT_DIR/build"
ditto --norsrc "$PRODUCTS_PATH/SitRight.app" "$STAGED_APP_PATH"

xattr -cr "$STAGED_APP_PATH"
clear_disallowed_xattrs "$STAGED_APP_PATH"

SIGN_IDENTITY="${SITRIGHT_CODE_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)"
fi

if [ -n "$SIGN_IDENTITY" ]; then
  /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --entitlements "$ROOT_DIR/WidgetBundle/SitRightWidgetExtension.entitlements" --generate-entitlement-der "$WIDGET_PATH"
  clear_disallowed_xattrs "$WIDGET_PATH"
  /usr/bin/codesign --verify --strict "$WIDGET_PATH"
  /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --entitlements "$ROOT_DIR/AppBundle/SitRight.entitlements" --generate-entitlement-der "$STAGED_APP_PATH"
fi

clear_root_disallowed_xattrs "$STAGED_APP_PATH"

if [ -n "$SIGN_IDENTITY" ]; then
  /usr/bin/codesign --verify --strict "$WIDGET_PATH"
  /usr/bin/codesign --verify --strict --deep "$STAGED_APP_PATH"
fi

verify_app_group_entitlement "$STAGED_APP_PATH" "SitRight.app"
verify_app_group_entitlement "$WIDGET_PATH" "SitRightWidgetExtension.appex"

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

ditto --norsrc "$STAGED_APP_PATH" "$APP_PATH"

unregister_transient_app "$PRODUCTS_PATH/SitRight.app"

if [ "${SITRIGHT_INSTALL_TO_APPLICATIONS:-0}" = "1" ]; then
  install_to_applications "$APP_PATH" "$INSTALL_APP_PATH"
  echo "$INSTALL_APP_PATH"
fi

if [ "${SITRIGHT_KEEP_DERIVED_DATA:-0}" = "1" ]; then
  echo "Kept DerivedData: $DERIVED_DATA_PATH" >&2
fi

echo "$APP_PATH"
