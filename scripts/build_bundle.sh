#!/bin/bash
# 완전 봉인 번들 빌드 — 받아서 실행되는 self-contained 배포본.
#
# 산출물 dist/NoiseCleaner/ 는 uv·파이썬·ffmpeg·brew가 전혀 없는 Mac에서도
# 그대로 돈다. 세 개의 relocatable venv(각자 파이썬 동봉), 앱 코드, 동봉
# ffmpeg, uv 바이너리, 더블클릭 런처를 담는다.
#
# 원리(실증됨): python-build-standalone는 설계상 재배치 가능. venv를
# --relocatable로 만들고 bin/python 심링크를 상대경로로 고치면, 번들을 어디로
# 옮기든 깨끗한 PATH에서 무거운 네이티브 확장(mlx·torch)까지 로드된다.
#
# 사용: bash scripts/build_bundle.sh
#   빌드에는 uv가 필요(개발 기기). 런타임에는 필요 없음.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist/NoiseCleaner"
RT="$DIST/runtime"
WITH_MODELS=0
[ "${1:-}" = "--with-models" ] && WITH_MODELS=1

command -v uv >/dev/null 2>&1 || { echo "빌드에는 uv 필요"; exit 1; }
PY312_SRC="$(dirname "$(dirname "$(uv python find 3.12)")")"
PY311_SRC="$(dirname "$(dirname "$(uv python find 3.11)")")"

echo "▸ 초기화: $DIST"
rm -rf "$DIST"; mkdir -p "$RT"

echo "▸ 파이썬 런타임 동봉 (3.12 + 3.11)"
cp -R "$PY312_SRC/." "$RT/py312/"
cp -R "$PY311_SRC/." "$RT/py311/"

# 공통: relocatable venv 만들고 bin/python 심링크를 상대경로로 고정
mk_reloc_venv() {  # $1=venv경로  $2=번들파이썬bin
  uv venv --relocatable --python "$2" "$1" >/dev/null
  local rel; rel="$(python3 -c "import os,sys; print(os.path.relpath('$2', '$1/bin'))")"
  ln -sf "$rel" "$1/bin/python"
  ln -sf python "$1/bin/python3"
  ln -sf python "$1/bin/python3.12" 2>/dev/null || true
  ln -sf python "$1/bin/python3.11" 2>/dev/null || true
}

echo "▸ 메인 환경 (.venv, py3.12) — 잠긴 의존성"
mk_reloc_venv "$RT/.venv" "$RT/py312/bin/python3.12"
uv export --frozen --no-dev --no-emit-project -o "$DIST/.reqs.txt" 2>/dev/null
VIRTUAL_ENV="$RT/.venv" uv pip install -q -r "$DIST/.reqs.txt"
rm -f "$DIST/.reqs.txt"

echo "▸ 하이브리드 노이즈 제거 엔진 (.venv-dfn, py3.11)"
mk_reloc_venv "$RT/.venv-dfn" "$RT/py311/bin/python3.11"
VIRTUAL_ENV="$RT/.venv-dfn" uv pip install -q \
  "deepfilternet==0.5.6" "torch==2.1.2" "torchaudio==2.1.2" \
  "soundfile==0.14.0" "numpy<2"

echo "▸ 재합성 엔진 (.venv-re, py3.11) + deepspeed 스텁"
mk_reloc_venv "$RT/.venv-re" "$RT/py311/bin/python3.11"
VIRTUAL_ENV="$RT/.venv-re" uv pip install -q resemble-enhance --no-deps
VIRTUAL_ENV="$RT/.venv-re" uv pip install -q torch torchaudio "numpy<2" \
  librosa soundfile rich tqdm resampy tabulate omegaconf pandas matplotlib \
  huggingface_hub
bash "$ROOT/scripts/_deepspeed_stub.sh" "$RT/.venv-re"

echo "▸ 앱 코드·모델 복사"
for d in core web voice models docs; do cp -R "$ROOT/$d" "$DIST/$d"; done
cp "$ROOT/denoise.py" "$ROOT/evaluate.py" "$ROOT/pyproject.toml" \
   "$ROOT/uv.lock" "$ROOT/README.md" "$ROOT/PORTABILITY.md" "$DIST/"
find "$DIST" -name "__pycache__" -type d -prune -exec rm -rf {} + 2>/dev/null || true

if [ "$WITH_MODELS" = "1" ]; then
  echo "▸ 오프라인 모델 동봉 (--with-models)"
  HFB="$DIST/models/hf/hub"; mkdir -p "$HFB"
  HFCACHE="$HOME/.cache/huggingface/hub"
  REPOS="mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit
mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit
mlx-community/whisper-large-v3-turbo
mlx-community/whisper-base-mlx"
  for repo in $REPOS; do
    dir="models--${repo//\//--}"
    if [ -d "$HFCACHE/$dir" ]; then
      echo "  · 캐시 재사용: $repo"; cp -R "$HFCACHE/$dir" "$HFB/"
    else
      echo "  · 다운로드: $repo"
      HF_HOME="$DIST/models/hf" "$RT/.venv/bin/python" -c \
        "from huggingface_hub import snapshot_download; snapshot_download('$repo')"
    fi
  done
  # resemble-enhance: enhancer_stage2만
  redir="models--ResembleAI--resemble-enhance"
  if [ -d "$HFCACHE/$redir" ]; then cp -R "$HFCACHE/$redir" "$HFB/"; else
    HF_HOME="$DIST/models/hf" "$RT/.venv/bin/python" -c \
      "from huggingface_hub import snapshot_download; snapshot_download('ResembleAI/resemble-enhance', allow_patterns=['enhancer_stage2/*'])"; fi
  # UTMOS (torch.hub) — PNS 북극성 점수용
  echo "  · UTMOS (torch.hub)"
  TORCH_HOME="$DIST/models/torch" "$RT/.venv/bin/python" -c \
    "import torch; torch.hub.load('tarepan/SpeechMOS:v1.2.0','utmos22_strong',trust_repo=True,skip_validation=True)" \
    2>/dev/null || cp -R "$HOME/.cache/torch" "$DIST/models/torch"
  echo "  (DFN·Resemblyzer 모델은 패키지 동봉, RNNoise는 models/ 에 포함)"
fi

echo "▸ uv 바이너리 동봉 (엔진 업데이트·재빌드용, 런타임 필수 아님)"
mkdir -p "$RT/bin"; cp "$(command -v uv)" "$RT/bin/uv"

echo "▸ 런처 생성"
cp "$ROOT/scripts/launcher.command" "$DIST/노이즈클리너 실행.command"
chmod +x "$DIST/노이즈클리너 실행.command"

SIZE=$(du -sh "$DIST" | cut -f1)
echo
echo "✅ 번들 완성: $DIST  ($SIZE)"
echo "   더블클릭: '$DIST/노이즈클리너 실행.command'"
if [ "$WITH_MODELS" = "1" ]; then
  echo "   완전 오프라인 — 모델까지 동봉됨. 네트워크 없이 바로 실행."
else
  echo "   모델은 최초 실행 시 자동 다운로드 (온라인). 완전 오프라인: --with-models"
fi
