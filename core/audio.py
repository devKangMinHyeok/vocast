"""ffmpeg 래퍼 유틸."""
import shutil
import subprocess


def ensure_ffmpeg():
    if not shutil.which("ffmpeg"):
        raise RuntimeError("ffmpeg이 필요합니다. 설치: brew install ffmpeg")


def has_video_stream(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries",
         "stream=codec_type", "-of", "csv=p=0", path],
        capture_output=True, text=True)
    return "video" in out.stdout


def run_ffmpeg(args):
    """ffmpeg 실행 (에러 출력 캡처). 실패 시 stderr를 담은 RuntimeError."""
    proc = subprocess.run(["ffmpeg", "-y", "-v", "error", *args],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"ffmpeg 실패: {proc.stderr[-400:]}")


def audio_codec_args(out_ext):
    """출력 확장자에 맞는 오디오 코덱 인자."""
    if out_ext == ".wav":
        return ["-c:a", "pcm_s16le"]
    return ["-c:a", "aac", "-b:a", "192k"]


def default_output_ext(in_ext):
    """입력 확장자에 대한 권장 출력 확장자 (mp3는 재인코딩 대신 m4a로)."""
    return ".m4a" if in_ext == ".mp3" else in_ext


SPEECH_TARGET_DB = -19.0  # 발화 RMS 목표 (유튜브/팟캐스트 배포 기준 -19~-16)
PEAK_CEILING_DB = -1.5    # 클리핑 방지 피크 상한


def normalize_gain_db(active_rms_db, peak_db,
                      target_db=SPEECH_TARGET_DB, ceiling_db=PEAK_CEILING_DB):
    """발화 RMS를 목표로 올리되 피크가 상한을 넘지 않는 게인(dB). 순수 함수."""
    gain = target_db - active_rms_db
    return min(gain, ceiling_db - peak_db)


def normalize_speech_level(wav_path, target_db=SPEECH_TARGET_DB):
    """정적 게인 음량 정규화 — 무음은 무음으로 유지(동적 펌핑 없음).

    클론 출력은 참조 녹음의 (대개 작은) 음량을 물려받는다 → 배포 기준으로 보정.
    """
    import numpy as np
    import soundfile as sf
    y, sr = sf.read(wav_path, dtype="float32")
    if y.ndim > 1:
        y = y.mean(axis=1)
    peak = np.abs(y).max()
    if peak < 1e-6:
        return wav_path
    hop = int(sr * 0.03)
    nf = len(y) // hop
    db = 20 * np.log10(np.maximum(
        np.sqrt((y[: nf * hop].reshape(nf, hop) ** 2).mean(axis=1)), 1e-9))
    active = db[db > db.max() - 30]  # 발화 구간만
    active_rms_db = float(10 * np.log10(np.mean(10 ** (active / 10))))
    gain_db = normalize_gain_db(active_rms_db, float(20 * np.log10(peak)),
                                target_db=target_db)
    if abs(gain_db) < 0.5:
        return wav_path
    sf.write(wav_path, y * (10 ** (gain_db / 20)), sr)
    return wav_path
