#!/bin/bash
# 맥 앱(.app 번들) 빌드 스크립트.
# 실행하면 dist/NoiseCleaner.app 이 만들어진다.
# 앱을 더블클릭하면: 로컬 서버를 켜고 → 브라우저로 웹 UI를 연다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/NoiseCleaner.app"
PORT=8756

# 파이썬 가상환경 준비 (없으면 생성 + flask 설치)
if [ ! -x "$ROOT/.venv/bin/python3" ]; then
  echo "가상환경 생성 중..."
  python3 -m venv "$ROOT/.venv"
  "$ROOT/.venv/bin/pip" install -q -r "$ROOT/requirements.txt"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>노이즈 클리너</string>
  <key>CFBundleDisplayName</key><string>노이즈 클리너</string>
  <key>CFBundleExecutable</key><string>run</string>
  <key>CFBundleIdentifier</key><string>dev.minhyeok.noisecleaner</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict>
</plist>
PLIST

cat > "$APP/Contents/MacOS/run" <<LAUNCHER
#!/bin/bash
ROOT="$ROOT"
PORT=$PORT
PY="\$ROOT/.venv/bin/python3"
[ -x "\$PY" ] || PY=python3

if ! curl -s "http://127.0.0.1:\$PORT/api/health" >/dev/null 2>&1; then
  nohup "\$PY" "\$ROOT/web/server.py" --port "\$PORT" > /tmp/noisecleaner.log 2>&1 &
  for i in \$(seq 1 40); do
    curl -s "http://127.0.0.1:\$PORT/api/health" >/dev/null 2>&1 && break
    sleep 0.25
  done
fi
open "http://127.0.0.1:\$PORT"
LAUNCHER

chmod +x "$APP/Contents/MacOS/run"
echo "완성: $APP"
echo "더블클릭하거나: open '$APP'"
