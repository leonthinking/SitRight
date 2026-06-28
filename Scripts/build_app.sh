#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${TMPDIR:-/private/tmp}/SitRightDerivedData"
PRODUCTS_PATH="$DERIVED_DATA_PATH/Build/Products/Release"
APP_PATH="$ROOT_DIR/build/SitRight.app"
STAGED_APP_PATH="$DERIVED_DATA_PATH/Signed/SitRight.app"
WIDGET_PATH="$STAGED_APP_PATH/Contents/PlugIns/SitRightWidgetExtension.appex"

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

cd "$ROOT_DIR"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/clang-module-cache}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required to build SitRight.app with the WidgetKit extension." >&2
  exit 1
fi

xcodegen generate
rm -rf "$DERIVED_DATA_PATH"

xcodebuild \
  -project "$ROOT_DIR/SitRight.xcodeproj" \
  -scheme SitRight \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

rm -rf "$STAGED_APP_PATH" "$APP_PATH"
mkdir -p "$(dirname "$STAGED_APP_PATH")" "$ROOT_DIR/build"
ditto --norsrc "$PRODUCTS_PATH/SitRight.app" "$STAGED_APP_PATH"

xattr -cr "$STAGED_APP_PATH"
clear_disallowed_xattrs "$STAGED_APP_PATH"

SIGN_IDENTITY="${SITRIGHT_CODE_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)"
fi

if [ -n "$SIGN_IDENTITY" ]; then
  /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --entitlements "$ROOT_DIR/WidgetBundle/SitRightWidgetExtension.entitlements" "$WIDGET_PATH"
  clear_disallowed_xattrs "$WIDGET_PATH"
  /usr/bin/codesign --verify --strict "$WIDGET_PATH"
  /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --entitlements "$ROOT_DIR/AppBundle/SitRight.entitlements" "$STAGED_APP_PATH"
fi

clear_root_disallowed_xattrs "$STAGED_APP_PATH"

/usr/bin/codesign --verify --strict "$WIDGET_PATH"
/usr/bin/codesign --verify --strict --deep "$STAGED_APP_PATH"

ditto --norsrc "$STAGED_APP_PATH" "$APP_PATH"

echo "$APP_PATH"
