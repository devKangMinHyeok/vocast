#!/usr/bin/env python3
"""resemble-enhance 재합성 워커 — 전용 venv(.venv-re)에서 실행.

노이즈를 "지우는" 게 아니라 깨끗한 음성을 다시 그려낸다(생성형 복원).
발화 중에 겹친 노이즈까지 원리적으로 제거되지만, 목소리가 미묘하게 변할 수
있어 앱 계층이 목소리 유사도(SIM)를 함께 리포트한다.

실측으로 확정한 설정:
- 디바이스 CPU 고정: MPS는 수치가 깨져 무성/저품질 출력 (SIM 0.355 vs 0.879)
- nfe=16: 32 대비 30% 빠르고 SIM 동등 (0.886 vs 0.879)
- lambd=0.9: 내장 denoiser를 강하게 (우리 용도는 항상 '노이즈 낀 입력')
- 모델은 huggingface_hub 캐시에서 로드 (git-lfs 불필요)

사용: python3 resynth_worker.py <in.wav> <out.wav>
"""
import sys
from pathlib import Path


def main():
    in_wav, out_wav = sys.argv[1], sys.argv[2]
    import soundfile as sf
    import torch
    from huggingface_hub import snapshot_download
    run_dir = Path(snapshot_download(
        "ResembleAI/resemble-enhance",
        allow_patterns=["enhancer_stage2/*"])) / "enhancer_stage2"
    from resemble_enhance.enhancer.inference import enhance
    y, sr = sf.read(in_wav, dtype="float32")
    if y.ndim > 1:
        y = y.mean(axis=1)
    wav, new_sr = enhance(torch.from_numpy(y), sr, "cpu", nfe=16,
                          solver="midpoint", lambd=0.9, tau=0.5,
                          run_dir=run_dir)
    sf.write(out_wav, wav.cpu().numpy(), new_sr)


if __name__ == "__main__":
    main()
