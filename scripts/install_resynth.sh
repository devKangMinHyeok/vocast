#!/bin/bash
# 재합성(resemble-enhance) 엔진 설치 — 전용 py3.11 venv (.venv-re)
#
# 왜 전용 venv인가: resemble-enhance는 torchaudio==2.1.1 등 구버전을 고정하고
# deepspeed(학습용, Mac 미설치)를 의존성에 포함한다. 본 venv를 오염시키지 않고
# --no-deps로 깔아 추론에 필요한 것만 채운다 (DFN의 .venv-dfn과 같은 패턴).
#
# 실측으로 확정한 것:
# - deepspeed는 추론 경로에서 심볼만 참조 → 최소 스텁으로 대체
# - numpy 2.x에서 CFM 솔버의 float(fsolve(...)) 가 죽음 → numpy<2 고정
# - torchaudio 2.11의 load는 torchcodec 요구 → IO는 soundfile로 (워커가 처리)
# - 모델은 git-lfs 대신 huggingface_hub로 받는다 (워커가 run_dir 직접 지정)
set -e
cd "$(dirname "$0")/.."

python3.11 -m venv .venv-re
./.venv-re/bin/pip install --upgrade pip
./.venv-re/bin/pip install resemble-enhance --no-deps
./.venv-re/bin/pip install torch torchaudio "numpy<2" librosa soundfile \
  rich tqdm resampy tabulate omegaconf pandas matplotlib huggingface_hub

SP=$(./.venv-re/bin/python3 -c "import site; print(site.getsitepackages()[0])")
mkdir -p "$SP/deepspeed/accelerator" "$SP/deepspeed/runtime" "$SP/deepspeed/ops/adam"
cat > "$SP/deepspeed/__init__.py" <<'EOF'
"""추론용 스텁 — resemble-enhance는 학습 경로에서만 deepspeed를 실제로 쓴다."""
class DeepSpeedConfig:
    def __init__(self, *a, **k): pass
def init_distributed(*a, **k):
    raise RuntimeError("deepspeed stub: 학습은 지원하지 않습니다")
def initialize(*a, **k):
    raise RuntimeError("deepspeed stub: 학습은 지원하지 않습니다")
EOF
cat > "$SP/deepspeed/accelerator/__init__.py" <<'EOF'
class _CPUAccel:
    def communication_backend_name(self): return "gloo"
    def device_name(self, *a): return "cpu"
def get_accelerator(): return _CPUAccel()
EOF
: > "$SP/deepspeed/runtime/__init__.py"
cat > "$SP/deepspeed/runtime/engine.py" <<'EOF'
class DeepSpeedEngine:
    def __init__(self, *a, **k):
        raise RuntimeError("deepspeed stub: 학습은 지원하지 않습니다")
EOF
cat > "$SP/deepspeed/runtime/utils.py" <<'EOF'
def clip_grad_norm_(*a, **k):
    raise RuntimeError("deepspeed stub")
EOF
: > "$SP/deepspeed/ops/__init__.py"
cat > "$SP/deepspeed/ops/adam/__init__.py" <<'EOF'
class FusedAdam:
    def __init__(self, *a, **k):
        raise RuntimeError("deepspeed stub")
EOF

./.venv-re/bin/python3 -c "from resemble_enhance.enhancer.inference import enhance; print('resemble-enhance OK')"
echo "완료 — 서버를 재시작하면 노이즈 제거 탭에 '재합성' 모드가 나타납니다"
