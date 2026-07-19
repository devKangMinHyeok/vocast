#!/bin/bash
# Package the native Vocast Mac app with the Python engine embedded inside the .app.
#
# Produces apps/mac/build/Vocast.app with Contents/Resources/engine holding a
# relocatable Python runtime + the engine source, so the app runs the sidecar from
# its own bundle (no dev repo, no system Python needed). Models are NOT bundled; the
# app downloads them on first run into ~/Library/Application Support/Vocast/models.
#
#   bash apps/mac/build_app.sh                 # beta build, ad-hoc signed
#   VOCAST_VARIANT=release bash apps/mac/build_app.sh
#   VOCAST_SIGN_ID="Developer ID Application: NAME (TEAMID)" \
#   VOCAST_NOTARY_PROFILE="vocast-notary" \
#     VOCAST_VARIANT=release bash apps/mac/build_app.sh   # signed + notarized
#
# Variants exist so a test build is never mistaken for the real one: beta gets a cyan
# icon, its own name and its own bundle id, so both can sit in /Applications together.
# The default is beta, because an unnotarized build is a test build by definition.
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

VARIANT="${VOCAST_VARIANT:-beta}"
case "$VARIANT" in
  release) APP_NAME="Vocast";      BUNDLE_ID="me.vocast.Vocast";      APPICON="AppIcon" ;;
  beta)    APP_NAME="Vocast Beta"; BUNDLE_ID="me.vocast.Vocast.beta"; APPICON="AppIconBeta" ;;
  *) echo "❌ VOCAST_VARIANT must be release or beta (got: $VARIANT)"; exit 1 ;;
esac
echo "▸ Variant: $VARIANT  ($APP_NAME, $BUNDLE_ID, icon $APPICON)"

# Reusing an already staged engine turns a ten-minute rebuild into a Swift-only one.
# Only safe while the Python side is untouched, so it is opt-in.
if [ "${VOCAST_SKIP_ENGINE:-0}" = "1" ] && [ -f "$STAGE/api/server.py" ]; then
  echo "▸ Reusing the staged engine at $STAGE (VOCAST_SKIP_ENGINE=1)"
  SKIP_ENGINE=1
else
  SKIP_ENGINE=0
fi

if [ "$SKIP_ENGINE" = "0" ]; then
command -v uv >/dev/null 2>&1 || { echo "❌ uv is required to build the engine"; exit 1; }

echo "▸ Building the embedded engine (main env only) → $STAGE"
rm -rf "$STAGE"; mkdir -p "$STAGE/runtime"
# Use a uv-managed (python-build-standalone) Python: it is relocatable, unlike a
# Homebrew/system Python. Force managed so the bundle is self-contained.
uv python install 3.12 >/dev/null 2>&1 || true
PY312_BIN="$(UV_PYTHON_PREFERENCE=only-managed uv python find 3.12)"
[ -x "$PY312_BIN" ] || { echo "❌ no uv-managed Python 3.12 found"; exit 1; }
PY312_SRC="$(dirname "$(dirname "$PY312_BIN")")"
echo "  managed python: $PY312_SRC"
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

echo "▸ Pruning parts of the venv that are never used at runtime"
SPKG="$STAGE/runtime/.venv/lib/python3.12/site-packages"
# libtorch C++ headers: only needed to compile extensions against torch, not to run it.
rm -rf "$SPKG/torch/include"
# DNSMOS (onnxruntime) and speaker similarity (resemblyzer) are quality-evaluation
# tools; the app never computes them while rendering or building a voice profile.
rm -rf "$SPKG/onnxruntime" "$SPKG/resemblyzer"
# sklearn must stay even though nothing here imports it directly: librosa.decompose
# does `import sklearn.decomposition` at module level, and librosa loads its submodules
# lazily, so it only surfaces once something touches librosa.effects. Removing it let
# `import librosa` succeed and then broke voice profile builds at the stats stage.
# torch itself has to stay, and so do torch/bin and torch/testing. Measured, not guessed:
#   - transformers imports torch at module load and mlx-audio's Qwen3 tokenizer goes
#     through transformers, so TTS generation fails outright without it,
#   - PNS is computed from UTMOS, which is a torch model, so dropping torch silently
#     turns off take scoring and paragraph metrics,
#   - torch/__init__ raises unless torch/bin/torch_shm_manager exists,
#   - torch.autograd.gradcheck imports torch.testing at load time.

echo "▸ Copying engine source (flat layout: engine root is the working dir)"
cp -R "$REPO/packages/voxa/voxa" "$STAGE/voxa"
for d in api voice cli; do cp -R "$PYAPP/$d" "$STAGE/$d"; done
cp "$PYAPP/pyproject.toml" "$PYAPP/uv.lock" "$STAGE/"
find "$STAGE" -name "__pycache__" -type d -prune -exec rm -rf {} + 2>/dev/null || true
fi   # end of engine staging

echo "▸ Regenerating app icons from the logo mark"
python3 "$HERE/make_icons.py" >/dev/null

echo "▸ Building the Release app"
xcodebuild -project "$PROJ" -scheme Vocast -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DD" \
  PRODUCT_NAME="$APP_NAME" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  ASSETCATALOG_COMPILER_APPICON_NAME="$APPICON" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO build >/dev/null
APP="$DD/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || { echo "❌ Release build not found at $APP"; exit 1; }

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

FINAL="$BUILD/$APP_NAME.app"
rm -rf "$FINAL"; cp -R "$APP" "$FINAL"
SIZE="$(du -sh "$FINAL" | cut -f1)"
echo "✅ Built: $FINAL  ($SIZE)"

# Notarization (needs a Developer ID signature + a stored notarytool profile):
#   xcrun notarytool store-credentials vocast-notary --apple-id you@ex.com --team-id TEAMID --password APP_SPECIFIC_PW
if [ -n "$SIGN_ID" ] && [ -n "${VOCAST_NOTARY_PROFILE:-}" ]; then
  echo "▸ Notarizing (this can take a few minutes)"
  ZIP="$BUILD/$APP_NAME.zip"
  ditto -c -k --keepParent "$FINAL" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$VOCAST_NOTARY_PROFILE" --wait
  xcrun stapler staple "$FINAL"
  echo "✅ Notarized and stapled: $FINAL"
else
  echo "ℹ️  Not notarized. For a distributable build, set VOCAST_SIGN_ID (Developer ID"
  echo "    Application) and VOCAST_NOTARY_PROFILE (xcrun notarytool store-credentials)."
fi

# ---- Disk image ----------------------------------------------------------------
# A .dmg is the packaging users expect: mount, drag the app onto the Applications
# alias, eject. It does not affect Gatekeeper; an unnotarized app still needs the
# user to allow it once, which FIRST-RUN.txt explains.
echo "▸ Building the disk image"
DMG="$BUILD/$APP_NAME.dmg"
DMGROOT="$BUILD/dmgroot"
rm -rf "$DMGROOT" "$DMG"; mkdir -p "$DMGROOT"
cp -R "$FINAL" "$DMGROOT/"
ln -s /Applications "$DMGROOT/Applications"

if [ -z "$SIGN_ID" ]; then
  cat > "$DMGROOT/FIRST-RUN.txt" <<TXT
$APP_NAME

Install
  Drag $APP_NAME onto the Applications folder in this window.

First launch
  This build is not notarized by Apple, so macOS blocks it the first time and may
  say the app is damaged. It is not damaged; macOS just cannot verify a build that
  has not been through Apple's notary service.

  To open it once:
    1. Open the Applications folder and try to launch $APP_NAME.
    2. Open System Settings, go to Privacy and Security, scroll to Security.
    3. Click Open Anyway next to the message about $APP_NAME, then confirm.

  Or, in Terminal:
    xattr -d com.apple.quarantine "/Applications/$APP_NAME.app"

What it needs
  Apple Silicon and macOS 14 or later. Everything runs on this Mac; the app never
  uploads audio. On first run it downloads the speech models it needs.
TXT
fi

hdiutil create -volname "$APP_NAME" -srcfolder "$DMGROOT" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$DMGROOT"
echo "✅ Disk image: $DMG  ($(du -sh "$DMG" | cut -f1))"
