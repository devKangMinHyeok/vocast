#!/bin/bash
# DeepFilterNet(하이브리드 노이즈 제거 엔진) 설치.
# 전용 py3.11 venv를 쓰는 이유: deepfilterlib이 3.12+ 휠이 없어 Rust 컴파일을
# 요구하고, torch 2.2+에서 구 torchaudio API가 제거되어 버전 핀이 필요하다.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PY=""
for p in python3.11 python3.10; do
  command -v "$p" >/dev/null 2>&1 && PY="$p" && break
done
[ -z "$PY" ] && { echo "python3.11이 필요합니다: brew install python@3.11"; exit 1; }

echo "DFN 전용 venv 생성 ($PY)..."
"$PY" -m venv "$ROOT/.venv-dfn"
"$ROOT/.venv-dfn/bin/pip" install -q --upgrade pip
"$ROOT/.venv-dfn/bin/pip" install -q deepfilternet "torch==2.1.2" "torchaudio==2.1.2" soundfile
"$ROOT/.venv-dfn/bin/python" -c "import df, torch; print('DeepFilterNet OK')"
echo "완료 — 이제 노이즈 제거가 자동으로 하이브리드(DFN) 엔진을 씁니다."
echo "(끄려면 .venv-dfn 폴더를 지우면 RNNoise로 폴백)"
