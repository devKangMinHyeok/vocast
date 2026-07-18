#!/bin/bash
# 노이즈 클리너 설치 (curl 파이프용).
#   curl -fsSL https://get.noisecleaner.app/install.sh | bash
#
# curl로 받으므로 quarantine 딱지가 붙지 않아 Gatekeeper 경고 없이 실행된다
# (브라우저로 .app을 받는 경우와 달리 코드 서명·공증이 불필요한 배포 경로).
#
# 설정(환경변수):
#   NC_URL     : 번들 tar.gz 직접 URL (기본: NC_RELEASE 기반 GitHub Releases)
#   NC_SHA256  : 무결성 검증 체크섬 (없으면 검증 생략 + 경고)
#   NC_PREFIX  : 설치 위치 (기본 ~/Applications/NoiseCleaner)
#   NC_BIN     : CLI 심링크 위치 (기본 ~/.local/bin)
set -euo pipefail

REPO="devKangMinHyeok/denoise-app"
NC_RELEASE="${NC_RELEASE:-latest}"
NC_PREFIX="${NC_PREFIX:-$HOME/Applications/NoiseCleaner}"
NC_BIN="${NC_BIN:-$HOME/.local/bin}"

say() { printf '\033[1;35m▸\033[0m %s\n' "$1"; }
die() { printf '\033[1;31m✗\033[0m %s\n' "$1" >&2; exit 1; }

# 1) 플랫폼 확인 (현재 Apple Silicon만)
[ "$(uname -s)" = "Darwin" ] || die "이 설치본은 macOS 전용입니다."
[ "$(uname -m)" = "arm64" ] || die "Apple Silicon(M1 이상) Mac이 필요합니다."

# 2) 다운로드 URL 결정
if [ -z "${NC_URL:-}" ]; then
  NC_URL="https://github.com/$REPO/releases/${NC_RELEASE}/download/NoiseCleaner-macos-arm64.tar.gz"
fi
say "다운로드: $NC_URL"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TARBALL="$TMP/nc.tar.gz"
curl -fL# "$NC_URL" -o "$TARBALL" || die "다운로드 실패."

# 3) 체크섬 검증 (제공 시)
if [ -n "${NC_SHA256:-}" ]; then
  say "무결성 검증 (sha256)"
  GOT="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"
  [ "$GOT" = "$NC_SHA256" ] || die "체크섬 불일치! 받은 파일을 신뢰할 수 없습니다."
else
  printf '\033[1;33m!\033[0m NC_SHA256 미지정 — 무결성 검증 생략\n'
fi

# 4) 설치 (기존 것 교체, 사용자 데이터 ~/.noisecleaner는 건드리지 않음)
say "설치: $NC_PREFIX"
rm -rf "$NC_PREFIX"; mkdir -p "$NC_PREFIX"
tar -xzf "$TARBALL" -C "$NC_PREFIX" --strip-components=1
# 방어적: 혹시 붙었을 quarantine 제거 (curl 경로엔 원래 없음)
xattr -dr com.apple.quarantine "$NC_PREFIX" 2>/dev/null || true

# 5) CLI 심링크
mkdir -p "$NC_BIN"
ln -sf "$NC_PREFIX/bin/noise-cleaner" "$NC_BIN/noise-cleaner"

say "완료!"
echo
echo "  실행:  noise-cleaner        (또는 더블클릭: '$NC_PREFIX/노이즈클리너 실행.command')"
echo "  브라우저에서 http://127.0.0.1:8756 가 열립니다."
case ":$PATH:" in
  *":$NC_BIN:"*) ;;
  *) echo
     echo "  참고: $NC_BIN 가 PATH에 없습니다. 아래를 셸 설정에 추가하세요:"
     echo "        export PATH=\"$NC_BIN:\$PATH\"" ;;
esac
