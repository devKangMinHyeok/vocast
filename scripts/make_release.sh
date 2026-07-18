#!/bin/bash
# 릴리스 아티팩트 생성: 번들 빌드 → tar.gz → sha256 → 배포 값 출력.
#
# 사용: bash scripts/make_release.sh [--with-models] [VERSION]
#
# ⚠️ 호스팅 주의: GitHub Releases는 파일당 2GB 제한이다. 우리 번들은
#    3.7GB(모델 없음)~11GB(--with-models)라 단일 GitHub 릴리스 에셋으로는
#    올라가지 않는다. 다음 중 하나를 쓴다:
#    (a) Cloudflare R2 / Backblaze B2 / S3 등 오브젝트 스토리지에 업로드하고
#        install.sh·cask의 URL을 그 주소로 (권장 — 대역폭 저렴)
#    (b) 2GB 미만으로 split 해서 GitHub Releases에 여러 파트로 올리고
#        install.sh가 재조립 (이 스크립트가 --split로 파트 생성)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WITH_MODELS=""
[ "${1:-}" = "--with-models" ] && { WITH_MODELS="--with-models"; shift; }
VERSION="${1:-$(grep -m1 '^version' "$ROOT/pyproject.toml" | cut -d'"' -f2)}"
OUT="$ROOT/dist/release"
NAME="NoiseCleaner-macos-arm64.tar.gz"

echo "▸ 번들 빌드 ${WITH_MODELS:-(모델 미포함)}"
bash "$ROOT/scripts/build_bundle.sh" $WITH_MODELS

echo "▸ 압축: $NAME"
mkdir -p "$OUT"
tar -C "$ROOT/dist" -czf "$OUT/$NAME" NoiseCleaner
SHA="$(shasum -a 256 "$OUT/$NAME" | awk '{print $1}')"
SIZE="$(du -h "$OUT/$NAME" | cut -f1)"

# 2GB 초과 시 split 안내/생성
BYTES="$(stat -f%z "$OUT/$NAME" 2>/dev/null || stat -c%s "$OUT/$NAME")"
echo
echo "════════ 릴리스 값 (install.sh / cask에 붙여넣기) ════════"
echo "  version : $VERSION"
echo "  file    : $OUT/$NAME  ($SIZE)"
echo "  sha256  : $SHA"
if [ "$BYTES" -gt 2000000000 ]; then
  echo
  echo "  ⚠️ 2GB 초과 → GitHub Releases 단일 업로드 불가."
  echo "     → R2/B2/S3에 업로드 후 그 URL을 NC_URL / cask url 로 쓰세요."
  echo "     또는 split: split -b 1900m '$OUT/$NAME' '$OUT/$NAME.part-'"
fi
echo "═══════════════════════════════════════════════════════════"
echo
echo "install.sh 배포 테스트(로컬):"
echo "  NC_URL=file://$OUT/$NAME NC_SHA256=$SHA bash scripts/install.sh"
