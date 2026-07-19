#!/bin/bash
# Package the native Vocast Mac app with the Python engine embedded inside the .app.
#
# Produces apps/mac/build/Vocast.app with Contents/Resources/engine holding a
# relocatable Python runtime + the engine source, so the app runs the sidecar from
# its own bundle (no dev repo, no system Python needed). Models are NOT bundled; the
# app downloads them on first run into ~/Library/Application Support/Vocast/models.
#
#   bash apps/mac/build_app.sh                 # ad-hoc signed (runs locally)
#   VOCAST_SIGN_ID="Developer ID Application: NAME (TEAMID)" \
#   VOCAST_NOTARY_PROFILE="vocast-notary" \
#     bash apps/mac/build_app.sh               # Developer ID signed + notarized
#
# Build needs uv (dev machine). The resulting app needs neither uv nor Python.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"          # apps/mac
REPO="$(cd "$HERE/../.." && pwd)"
PYAPP="$REPO/app"
PROJ="$HERE/Vocast/Vocast.xcodeproj"
BUILD="$HERE/build"
STAGE="$BUILD/engine"
DD="$BUILD/DerivedData"

command -v uv >/dev/null 2>&1 || { echo "❌ uv is required to build the engine"; exit 1; }

echo "▸ Building the embedded engine (main env only) → $STAGE"
rm -rf "$STAGE"; mkdir -p "$STAGE/runtime"
PY312_SRC="$(dirname "$(dirname "$(uv python find 3.12)")")"
cp -R "$PY312_SRC/." "$STAGE/runtime/py312/"

# Relocatable venv with a relative python symlink, so it works from inside the .app.
uv venv --relocatable --python "$STAGE/runtime/py312/bin/python3.12" "$STAGE/runtime/.venv" >/dev/null
REL="$(python3 -c "import os; print(os.path.relpath('$STAGE/runtime/py312/bin/python3.12','$STAGE/runtime/.venv/bin'))")"
ln -sf "$REL" "$STAGE/runtime/.venv/bin/python"
ln -sf python "$STAGE/runtime/.venv/bin/python3"
ln -sf python "$STAGE/runtime/.venv/bin/python3.12" 2>/dev/null || true

echo "▸ Installing locked deps into the embedded venv"
uv export --frozen --no-dev --no-emit-project --no-emit-package voxa --project "$PYAPP" -o "$BUILD/reqs.txt" 2>/dev/null
VIRTUAL_ENV="$STAGE/runtime/.venv" uv pip install -q -r "$BUILD/reqs.txt"
rm -f "$BUILD/reqs.txt"

echo "▸ Copying engine source (flat layout: engine root is the working dir)"
cp -R "$REPO/packages/voxa/voxa" "$STAGE/voxa"
for d in api voice cli; do cp -R "$PYAPP/$d" "$STAGE/$d"; done
cp "$PYAPP/pyproject.toml" "$PYAPP/uv.lock" "$STAGE/"
find "$STAGE" -name "__pycache__" -type d -prune -exec rm -rf {} + 2>/dev/null || true

echo "▸ Building the Release app"
xcodebuild -project "$PROJ" -scheme Vocast -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DD" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO build >/dev/null
APP="$DD/Build/Products/Release/Vocast.app"
[ -d "$APP" ] || { echo "❌ Release build not found"; exit 1; }

echo "▸ Embedding the engine into Contents/Resources/engine"
rm -rf "$APP/Contents/Resources/engine"
cp -R "$STAGE" "$APP/Contents/Resources/engine"

ENT="$HERE/Vocast/Vocast/Vocast.entitlements"
SIGN_ID="${VOCAST_SIGN_ID:-}"

if [ -n "$SIGN_ID" ]; then
  echo "▸ Signing nested code + app with Developer ID (hardened runtime)"
  # Sign every Mach-O in the embedded engine first (inside-out), then the app.
  find "$APP/Contents/Resources/engine" -type f \( -name "*.dylib" -o -name "*.so" -o -perm -u+x \) -print0 |
    while IFS= read -r -d '' f; do
      if file "$f" | grep -q "Mach-O"; then
        codesign --force --timestamp --options runtime --entitlements "$ENT" --sign "$SIGN_ID" "$f" 2>/dev/null || true
      fi
    done
  codesign --force --timestamp --options runtime --entitlements "$ENT" --sign "$SIGN_ID" "$APP"
else
  echo "▸ Ad-hoc signing (runs locally; not distributable). Set VOCAST_SIGN_ID to notarize."
  codesign --force --deep --sign - --entitlements "$ENT" "$APP" 2>/dev/null || codesign --force --deep --sign - "$APP"
fi

FINAL="$BUILD/Vocast.app"
rm -rf "$FINAL"; cp -R "$APP" "$FINAL"
SIZE="$(du -sh "$FINAL" | cut -f1)"
echo "✅ Built: $FINAL  ($SIZE)"

# Notarization (needs a Developer ID signature + a stored notarytool profile):
#   xcrun notarytool store-credentials vocast-notary --apple-id you@ex.com --team-id TEAMID --password APP_SPECIFIC_PW
if [ -n "$SIGN_ID" ] && [ -n "${VOCAST_NOTARY_PROFILE:-}" ]; then
  echo "▸ Notarizing (this can take a few minutes)"
  ZIP="$BUILD/Vocast.zip"
  ditto -c -k --keepParent "$FINAL" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$VOCAST_NOTARY_PROFILE" --wait
  xcrun stapler staple "$FINAL"
  echo "✅ Notarized and stapled: $FINAL"
else
  echo "ℹ️  Not notarized. For a distributable build, set VOCAST_SIGN_ID (Developer ID"
  echo "    Application) and VOCAST_NOTARY_PROFILE (xcrun notarytool store-credentials)."
fi
