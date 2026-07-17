"""배경 소음 제거 파이프라인.

엔진 2종:
- rnnoise (기본 폴백): ffmpeg arnndn. 무음 구간 억제는 강하나, 합성 벤치
  실측에서 말끝 클리핑(TPR -2.4dB)과 발화 중 잔존(SNR15에서 -1.8dB 악화).
- dfn (하이브리드, 설치 시 기본): DeepFilterNet3+PF 2패스 —
  발화 구간은 감쇠 상한 12dB + 말끝 hangover 0.3s로 보호, 무음 구간은
  풀억제 출력으로 블렌딩. 벤치 게이트 전부 통과
  (TPR -0.4/-0.1, 발화 중 개선 +6.5/+3.9dB, 무음 잔여 -63dBFS).
  설치: bash scripts/install_dfn.sh (전용 py3.11 venv — 상세는 스크립트 참고)
"""
import os
import subprocess
import sys

from . import ROOT, RNNOISE_MODEL
from .audio import audio_codec_args, has_video_stream, run_ffmpeg

DFN_VENV_PY = os.environ.get(
    "DFN_PYTHON", os.path.join(ROOT, ".venv-dfn", "bin", "python3"))


def dfn_available():
    """하이브리드(DFN) 엔진 사용 가능 여부."""
    return os.path.exists(DFN_VENV_PY)


def build_audio_filter(boost=0.0, model_path=RNNOISE_MODEL):
    """모노 변환 → RNNoise → (선택) 볼륨 업 필터 체인."""
    af = f"aformat=channel_layouts=mono,arnndn=m='{model_path}'"
    if boost:
        af += f",volume={boost}dB"
    return af


def preprocess_source(input_path, output_path, denoise=True, max_sec=180):
    """프로필 학습 소스 전처리: (선택) 노이즈 제거 + 모노 wav 변환 + 길이 제한.

    영상 파일도 받는다. 소스마다 노이즈 제거를 개별 선택할 수 있게
    변환과 제거를 한 단계로 묶은 헬퍼 (앱 계층은 이 함수만 호출).
    """
    af = build_audio_filter() if denoise else "aformat=channel_layouts=mono"
    args = ["-i", input_path]
    if max_sec:
        args += ["-t", str(max_sec)]
    args += ["-af", af, "-ac", "1", "-c:a", "pcm_s16le", output_path]
    run_ffmpeg(args)
    return output_path


def blend_hybrid(protected, full, sr, pause_gain_db=-25, hop_sec=0.03,
                 hang_pre=0.12, hang_post=0.30):
    """하이브리드 블렌딩 (순수 함수): 발화(+말끝 hangover)=protected,
    무음=full×게이트(-25dB).

    - VAD는 full(풀억제) 신호의 무음/발화 분포 **중간점 문턱** — 입력 SNR과
      무관하게 강건 (실측: 고정 오프셋 문턱은 저SNR·음성 블리드에서 실패).
    - 무음 브랜치에 게이트를 두는 이유: 실녹음의 무음엔 화자 음성의 잔향
      블리드가 섞일 수 있고, DFN은 음성 같은 성분을 보호해 안 지운다(실측:
      Whisper가 '노이즈'에서 단어를 받아씀). 게이트가 이를 -25dB 내린다.
    """
    import numpy as np
    L = min(len(protected), len(full))
    a, b = protected[:L], full[:L]
    hop = int(sr * hop_sec)
    nf = max(L // hop, 1)
    db = 20 * np.log10(np.maximum(
        np.sqrt((b[: nf * hop].reshape(nf, hop) ** 2).mean(axis=1)), 1e-9))
    valid = db > -110
    th = (np.percentile(db[valid], 10) + np.percentile(db[valid], 90)) / 2
    speech = db > th
    mask = np.zeros(nf)
    pre = max(1, int(hang_pre / hop_sec))
    post = max(1, int(hang_post / hop_sec))
    for i in np.where(speech)[0]:
        mask[max(0, i - pre): min(nf, i + post + 1)] = 1
    mask = np.convolve(mask, np.ones(3) / 3, mode="same")
    m = np.repeat(mask, hop)
    m = np.pad(m, (0, max(0, L - len(m))), mode="edge")[:L]
    g = 10 ** (pause_gain_db / 20)
    return a * m + b * (1 - m) * g


def _denoise_wav_dfn(in_wav, out_wav):
    """DFN 하이브리드로 wav 처리 (전용 venv 워커 호출 후 블렌딩)."""
    import numpy as np
    import soundfile as sf
    import tempfile
    worker = os.path.join(ROOT, "core", "dfn_worker.py")
    with tempfile.TemporaryDirectory() as wd:
        lim = os.path.join(wd, "lim.wav")
        unlim = os.path.join(wd, "unlim.wav")
        proc = subprocess.run([DFN_VENV_PY, worker, in_wav, lim, unlim],
                              capture_output=True, text=True, timeout=1800)
        if proc.returncode != 0:
            raise RuntimeError(f"DFN 워커 실패: {proc.stderr[-300:]}")
        a, sr = sf.read(lim, dtype="float32")
        b, _ = sf.read(unlim, dtype="float32")
        sf.write(out_wav, blend_hybrid(a, b, sr).astype(np.float32), sr)
    return out_wav


def run_denoise(input_path, output_path, boost=0.0, engine="auto"):
    """원본은 건드리지 않고, 소음 제거된 새 파일을 만든다. 영상은 무손실 복사.

    engine: "auto"(DFN 설치 시 하이브리드, 아니면 rnnoise) | "dfn" | "rnnoise"
    """
    if os.path.abspath(output_path) == os.path.abspath(input_path):
        raise ValueError("출력이 입력과 같은 파일입니다. 원본 보호를 위해 중단합니다.")
    use_dfn = (engine == "dfn") or (engine == "auto" and dfn_available())
    if use_dfn and not dfn_available():
        raise RuntimeError("DFN 엔진이 설치되어 있지 않습니다: bash scripts/install_dfn.sh")

    if not use_dfn:
        args = ["-i", input_path]
        if has_video_stream(input_path):
            args += ["-c:v", "copy"]
        args += ["-af", build_audio_filter(boost)]
        args += audio_codec_args(os.path.splitext(output_path)[1].lower())
        args.append(output_path)
        run_ffmpeg(args)
        return

    import tempfile
    with tempfile.TemporaryDirectory() as wd:
        raw = os.path.join(wd, "in.wav")
        run_ffmpeg(["-i", input_path, "-ac", "1", "-c:a", "pcm_s16le", raw])
        clean = os.path.join(wd, "clean.wav")
        _denoise_wav_dfn(raw, clean)
        post = f"volume={boost}dB" if boost else "anull"
        if has_video_stream(input_path):  # 원본 영상 + 새 오디오 재결합
            run_ffmpeg(["-i", input_path, "-i", clean, "-map", "0:v", "-map",
                        "1:a", "-c:v", "copy", "-af", post,
                        *audio_codec_args(os.path.splitext(output_path)[1].lower()),
                        output_path])
        else:
            run_ffmpeg(["-i", clean, "-af", post,
                        *audio_codec_args(os.path.splitext(output_path)[1].lower()),
                        output_path])
