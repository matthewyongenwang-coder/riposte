#!/usr/bin/env bash
# Builds Riposte.app with the tracking engine inside it, so the app runs with
# no terminal, no Python install and no copy of this repository.
#
#   scripts/build_mac_app.sh
#
# Output: dist/Riposte.app, which you can drag into Applications.
#
# The engine is frozen with PyInstaller rather than shipped as a copy of the
# venv, because a venv has this Mac's absolute paths baked into it and breaks
# the moment it moves. The models go inside the bundle too, so the app works
# offline from the first launch.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "1/4  Freezing the engine"
for model in yolox_person.onnx pose_landmarks.onnx vittrack.onnx; do
  if [ ! -f "models/$model" ]; then
    echo "models/$model is missing. Run: python3 get_models.py" >&2
    exit 1
  fi
done
# pose.py adds vendor/ to sys.path at runtime, which PyInstaller cannot see,
# so the vendored BlazePose module is named explicitly.
"$ROOT/venv/bin/pyinstaller" --noconfirm --clean --onedir --name riposte-engine \
  --paths "$ROOT" --paths "$ROOT/vendor" --hidden-import mp_pose \
  --add-data "$ROOT/models:models" \
  --distpath "$ROOT/build_engine/dist" --workpath "$ROOT/build_engine/work" \
  --specpath "$ROOT/build_engine" \
  "$ROOT/engine.py"

echo "2/4  Building the app"
(cd "$ROOT/app" && flutter build macos --release)

echo "3/4  Putting the engine inside the app"
APP_SRC="$ROOT/app/build/macos/Build/Products/Release/Riposte.app"
APP="$ROOT/dist/Riposte.app"
mkdir -p "$ROOT/dist"
rm -rf "$APP"
cp -R "$APP_SRC" "$APP"
mkdir -p "$APP/Contents/Resources/engine"
cp -R "$ROOT/build_engine/dist/riposte-engine/." "$APP/Contents/Resources/engine/"

echo "4/4  Signing for this Mac"
# Copying the engine in invalidates Flutter's signature, so the whole bundle
# is re-signed ad hoc. That is enough to run on the Mac that built it. Giving
# it to anyone else needs a Developer ID and notarisation.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP ($(du -sh "$APP" | cut -f1))"
