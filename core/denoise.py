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
RE_VENV_PY = os.environ.get(
    "RESYNTH_PYTHON", os.path.join(ROOT, ".venv-re", "bin", "python3"))


def dfn_available():
    """하이브리드(DFN) 엔진 사용 가능 여부."""
    return os.path.exists(DFN_VENV_PY)


def resynth_available():
    """재합성(resemble-enhance) 엔진 사용 가능 여부."""
    return os.path.exists(RE_VENV_PY)


def build_audio_filter(boost=0.0, model_path=RNNOISE_MODEL):
    """모노 변환 → RNNoise → (선택) 볼륨 업 필터 체인."""
    af = f"aformat=channel_layouts=mono,arnndn=m='{model_path}'"
    if boost:
        af += f",volume={boost}dB"
    return af


def denoise_to_wav(input_path, output_path, engine="auto", max_sec=None):
    """어떤 입력(영상 포함)이든 → 노이즈 제거된 모노 wav.

    참조 정리·프로필 전처리 등 '깨끗한 wav'가 필요한 모든 경로의 공용 진입점.
    engine="auto"면 DFN 하이브리드(설치 시), 아니면 RNNoise.
    """
    use_dfn = (engine == "dfn") or (engine == "auto" and dfn_available())
    if use_dfn:
        import tempfile
        with tempfile.TemporaryDirectory() as wd:
            raw = os.path.join(wd, "raw.wav")
            args = ["-i", input_path]
            if max_sec:
                args += ["-t", str(max_sec)]
            args += ["-ac", "1", "-c:a", "pcm_s16le", raw]
            run_ffmpeg(args)
            _denoise_wav_dfn(raw, output_path)
        return output_path
    args = ["-i", input_path]
    if max_sec:
        args += ["-t", str(max_sec)]
    args += ["-af", build_audio_filter(), "-ac", "1", "-c:a", "pcm_s16le",
             output_path]
    run_ffmpeg(args)
    return output_path


def preprocess_source(input_path, output_path, denoise=True, max_sec=180):
    """프로필 학습 소스 전처리: (선택) 노이즈 제거 + 모노 wav 변환 + 길이 제한.

    영상 파일도 받는다. 소스마다 노이즈 제거를 개별 선택할 수 있게
    변환과 제거를 한 단계로 묶은 헬퍼 (앱 계층은 이 함수만 호출).
    노이즈 제거는 엔진 디스패처(denoise_to_wav) 경유 — DFN 설치 시 하이브리드.
    """
    if denoise:
        return denoise_to_wav(input_path, output_path, max_sec=max_sec)
    args = ["-i", input_path]
    if max_sec:
        args += ["-t", str(max_sec)]
    args += ["-af", "aformat=channel_layouts=mono", "-ac", "1",
             "-c:a", "pcm_s16le", output_path]
    run_ffmpeg(args)
    return output_path


MIN_CLASS_SEP_DB = 12.0   # 무음/발화 두 무리의 평균 차 최소치 (이봉성 증거)
MIN_CLASS_FRAC = 0.05     # 각 무리가 최소 5%는 되어야 함


def vad_threshold(db_frames):
    """프레임 dB 배열 → 발화 문턱 (없으면 None = 게이트 생략). 순수 함수.

    Otsu 이진화(두 무리 분산을 최대로 가르는 문턱) + 이봉성 가드.

    실사용 사고로 배운 것: 무음/발화 '중간점(p10·p90 평균)' 문턱은 무음이
    거의 없는 연속 발화 녹음(화면 녹화 나레이션)에서 문턱이 발화 한가운데
    꽂혀 말끝을 죽이고(-25dB) 분당 20회씩 끊김을 만든다 (실측: 발화
    프레임의 64%가 무음 판정, 발화 프레임 18%가 15dB+ 손실). 무음 바닥
    +10dB 고정 오프셋도 실패 — 무음이 있는 녹음에선 문턱이 너무 낮아져
    무음 잔여 게이트(-55dBFS)가 깨진다 (실측 -48.7). 그래서:
    - Otsu로 분포를 두 무리로 가르고,
    - 두 무리 평균이 MIN_CLASS_SEP_DB 이상 벌어지고 양쪽 다 MIN_CLASS_FRAC
      이상일 때만 게이트 — 아니면 "무음 증거 없음"으로 게이트 생략.
      (게이트의 존재 이유는 긴 무음의 잔향 블리드 제거이므로,
      무음이 없으면 할 일도 없다.)
    """
    import numpy as np
    x = np.sort(np.asarray(db_frames, dtype=float))
    n = len(x)
    if n < 20:
        return None
    c1 = np.cumsum(x)
    i = np.arange(1, n)          # 하위 무리 크기 후보
    mu0 = c1[:-1] / i            # 하위(무음 쪽) 평균
    mu1 = (c1[-1] - c1[:-1]) / (n - i)  # 상위(발화 쪽) 평균
    between = i * (n - i) * (mu1 - mu0) ** 2  # 무리 간 분산 (Otsu)
    k = int(np.argmax(between))
    lo, hi = k + 1, n - k - 1
    if (mu1[k] - mu0[k] < MIN_CLASS_SEP_DB
            or lo < n * MIN_CLASS_FRAC or hi < n * MIN_CLASS_FRAC):
        return None
    return float((x[k] + x[k + 1]) / 2)


def blend_hybrid(protected, full, sr, pause_gain_db=-25, hop_sec=0.03,
                 hang_pre=0.12, hang_post=0.30):
    """하이브리드 블렌딩 (순수 함수): 발화(+말끝 hangover)=protected,
    무음=full×게이트(-25dB).

    - VAD 문턱은 vad_threshold — 무음 바닥+10dB, 무음 증거가 없으면
      게이트 생략(전 구간 protected). 문턱 산정 근거는 그 함수 주석 참고.
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
    # 디지털 무음(-inf 근처)은 제외하지 않고 -80으로 클램프해 '무음 무리'의
    # 증거로 포함 (제외하면 Otsu가 무음 클래스를 못 본다)
    th = vad_threshold(np.maximum(db, -80.0))
    if th is None:
        return a
    speech = db > th
    mask = np.zeros(nf)
    pre = max(1, int(hang_pre / hop_sec))
    post = max(1, int(hang_post / hop_sec))
    for i in np.where(speech)[0]:
        mask[max(0, i - pre): min(nf, i + post + 1)] = 1
    mask = np.convolve(mask, np.ones(5) / 5, mode="same")  # 150ms 램프 — 끊김 방지
    m = np.repeat(mask, hop)
    m = np.pad(m, (0, max(0, L - len(m))), mode="edge")[:L]
    g = 10 ** (pause_gain_db / 20)
    return a * m + b * (1 - m) * g


def _notify(on_progress, **event):
    """진행 콜백 (선택) — 앱 계층 시각화용. 실패해도 파이프라인은 계속."""
    if on_progress:
        try:
            on_progress(event)
        except Exception:
            pass


def _denoise_wav_dfn(in_wav, out_wav, on_progress=None):
    """DFN 하이브리드로 wav 처리 (전용 venv 워커 호출 후 블렌딩)."""
    import numpy as np
    import soundfile as sf
    import tempfile
    worker = os.path.join(ROOT, "core", "dfn_worker.py")
    with tempfile.TemporaryDirectory() as wd:
        lim = os.path.join(wd, "lim.wav")
        unlim = os.path.join(wd, "unlim.wav")
        _notify(on_progress, stage="denoise")
        proc = subprocess.run([DFN_VENV_PY, worker, in_wav, lim, unlim],
                              capture_output=True, text=True, timeout=1800)
        if proc.returncode != 0:
            raise RuntimeError(f"DFN 워커 실패: {proc.stderr[-300:]}")
        _notify(on_progress, stage="blend")
        a, sr = sf.read(lim, dtype="float32")
        b, _ = sf.read(unlim, dtype="float32")
        sf.write(out_wav, blend_hybrid(a, b, sr).astype(np.float32), sr)
    return out_wav


def _resynth_wav(in_wav, out_wav, on_progress=None):
    """재합성(resemble-enhance) 워커 호출 — CPU 고정 (설정 근거는 워커 주석)."""
    _notify(on_progress, stage="resynth")
    worker = os.path.join(ROOT, "core", "resynth_worker.py")
    proc = subprocess.run([RE_VENV_PY, worker, in_wav, out_wav],
                          capture_output=True, text=True, timeout=7200)
    if proc.returncode != 0 or not os.path.exists(out_wav):
        raise RuntimeError(f"재합성 워커 실패: {proc.stderr[-300:]}")
    return out_wav


def _finish_output(input_path, clean_wav, output_path, boost, on_progress):
    """정제된 오디오를 최종 컨테이너로 (영상이면 무손실 재결합)."""
    post = f"volume={boost}dB" if boost else "anull"
    _notify(on_progress, stage="remux")
    codec = audio_codec_args(os.path.splitext(output_path)[1].lower())
    if has_video_stream(input_path):
        run_ffmpeg(["-i", input_path, "-i", clean_wav, "-map", "0:v",
                    "-map", "1:a", "-c:v", "copy", "-af", post, *codec,
                    output_path])
    else:
        run_ffmpeg(["-i", clean_wav, "-af", post, *codec, output_path])


def run_denoise(input_path, output_path, boost=0.0, engine="auto",
                mode="standard", on_progress=None):
    """원본은 건드리지 않고, 소음 제거된 새 파일을 만든다. 영상은 무손실 복사.

    mode:
    - "standard": 필터형 — DFN 하이브리드(설치 시) 또는 RNNoise.
      발화 보존이 우선이라 발화 중에 겹친 노이즈는 일부 남는다 (12dB 상한).
    - "resynth": 생성형 재합성(resemble-enhance) — 깨끗한 음성을 다시
      그려내 발화 중 노이즈까지 원리적으로 제거. 목소리가 미묘하게 변할 수
      있으므로 앱 계층이 SIM(목소리 유사도)을 함께 리포트할 것.
    engine: "auto" | "dfn" | "rnnoise" (standard 모드에서만 의미)
    on_progress: 단계 콜백 {"stage": extract|denoise|blend|resynth|remux}
    """
    if os.path.abspath(output_path) == os.path.abspath(input_path):
        raise ValueError("출력이 입력과 같은 파일입니다. 원본 보호를 위해 중단합니다.")
    if mode not in ("standard", "resynth"):
        raise ValueError(f"알 수 없는 모드: {mode}")

    import tempfile
    if mode == "resynth":
        if not resynth_available():
            raise RuntimeError(
                "재합성 엔진이 설치되어 있지 않습니다: bash scripts/install_resynth.sh")
        from .audio import normalize_speech_level
        with tempfile.TemporaryDirectory() as wd:
            raw = os.path.join(wd, "in.wav")
            _notify(on_progress, stage="extract")
            run_ffmpeg(["-i", input_path, "-ac", "1", "-c:a", "pcm_s16le", raw])
            # 실측: 작은 레벨 입력은 재합성이 붕괴(무성 출력) → 레벨 선보정 필수
            normalize_speech_level(raw)
            clean = os.path.join(wd, "resynth.wav")
            _resynth_wav(raw, clean, on_progress=on_progress)
            _finish_output(input_path, clean, output_path, boost, on_progress)
        return

    use_dfn = (engine == "dfn") or (engine == "auto" and dfn_available())
    if use_dfn and not dfn_available():
        raise RuntimeError("DFN 엔진이 설치되어 있지 않습니다: bash scripts/install_dfn.sh")

    if not use_dfn:
        _notify(on_progress, stage="denoise")
        args = ["-i", input_path]
        if has_video_stream(input_path):
            args += ["-c:v", "copy"]
        args += ["-af", build_audio_filter(boost)]
        args += audio_codec_args(os.path.splitext(output_path)[1].lower())
        args.append(output_path)
        run_ffmpeg(args)
        return

    with tempfile.TemporaryDirectory() as wd:
        raw = os.path.join(wd, "in.wav")
        _notify(on_progress, stage="extract")
        run_ffmpeg(["-i", input_path, "-ac", "1", "-c:a", "pcm_s16le", raw])
        clean = os.path.join(wd, "clean.wav")
        _denoise_wav_dfn(raw, clean, on_progress=on_progress)
        _finish_output(input_path, clean, output_path, boost, on_progress)


def voice_similarity(src_path, out_path, max_sec=60):
    """원본↔결과 화자 유사도 (재합성 모드의 감시 지표). 미설치 시 None.

    재합성은 음성을 다시 그리므로 "노이즈 0"이 목소리 변형의 대가일 수 있다.
    SIM ≥ 0.85(클로닝과 같은 게이트)면 같은 목소리로 인정.
    """
    try:
        import numpy as np
        from resemblyzer import VoiceEncoder, preprocess_wav
    except ImportError:
        return None
    import tempfile
    enc = VoiceEncoder()
    embs = []
    with tempfile.TemporaryDirectory() as wd:
        for i, p in enumerate((src_path, out_path)):
            w = os.path.join(wd, f"{i}.wav")
            run_ffmpeg(["-i", p, "-t", str(max_sec), "-ac", "1",
                        "-ar", "16000", "-c:a", "pcm_s16le", w])
            embs.append(enc.embed_utterance(preprocess_wav(w)))
    return round(float(np.dot(embs[0], embs[1])), 3)


def report_from_frames(orig_db, out_db):
    """원본/결과 프레임 dB → 품질 리포트 (순수 함수, 볼륨 업과 무관).

    - speech_loss_pct: 발화 프레임 중 (전체 발화 감쇠 대비) 15dB+ 더 깎인
      비율 — "말끝이 사라진다" 결함의 지표. 정상 0%.
    - pause_supp_db: 무음이 발화보다 얼마나 더 눌렸는지(+) — 소음 억제량.
    """
    import numpy as np
    L = min(len(orig_db), len(out_db))
    da, db_ = np.asarray(orig_db[:L]), np.asarray(out_db[:L])
    p90 = np.percentile(da, 90)
    # 무음 = 발화 대역(-20dB) 아래로 2dB 여유 — 팬 소음 낀 실녹음의 바닥도
    # 잡히도록 (p90-40은 SNR 20dB대 녹음에서 무음을 하나도 못 찾았다)
    sp, pa = da > p90 - 20, da < p90 - 22
    att = db_ - da
    ref = float(np.median(att[sp])) if sp.any() else 0.0
    loss = float((sp & (att - ref < -15)).sum() / max(sp.sum(), 1)) * 100
    supp = ref - float(np.median(att[pa])) if pa.any() else 0.0
    return {"speech_loss_pct": round(loss, 1),
            "pause_supp_db": round(supp, 1)}


def denoise_report(src_path, out_path, max_sec=600):
    """원본 대비 결과 품질 실측 (UI 표시용) — 발화 보존·무음 억제."""
    import soundfile as sf
    import numpy as np
    import tempfile
    with tempfile.TemporaryDirectory() as wd:
        frames = []
        for p in (src_path, out_path):
            w = os.path.join(wd, f"{len(frames)}.wav")
            run_ffmpeg(["-i", p, "-t", str(max_sec), "-ac", "1",
                        "-ar", "48000", "-c:a", "pcm_s16le", w])
            y, sr = sf.read(w, dtype="float32")
            hop = int(sr * 0.03)
            nf = max(len(y) // hop, 1)
            frames.append(20 * np.log10(np.maximum(np.sqrt(
                (y[: nf * hop].reshape(nf, hop) ** 2).mean(axis=1)), 1e-9)))
    return report_from_frames(frames[0], frames[1])
