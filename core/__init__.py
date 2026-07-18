"""Vocast 핵심 로직 패키지.

- core.audio   : ffmpeg 래퍼 (스트림 검사, 오디오 추출)
- core.denoise : 배경 소음 제거 파이프라인 (RNNoise)
- core.clone   : 보이스 클로닝 파이프라인 (Qwen3-TTS)
- core.metrics : 품질 평가 지표 (SIM / CER / DNSMOS / 북극성 점수)

CLI(denoise.py, voice/clone_say.py), 웹 서버(web/server.py), CI(quality/)가
전부 이 패키지 하나만 바라본다.
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS_DIR = os.path.join(ROOT, "models")
RNNOISE_MODEL = os.path.join(MODELS_DIR, "rnnoise-sh.rnnn")
DNSMOS_MODEL = os.path.join(MODELS_DIR, "dnsmos_sig_bak_ovr.onnx")

import threading

MLX_LOCK = threading.Lock()


def mlx_transcribe(wav_path, **kwargs):
    """mlx_whisper.transcribe 직렬화 래퍼.

    MLX는 한 프로세스에서 여러 스레드가 동시에 쓰면 안전하지 않다
    (실측: 클론 채점과 프로필 분석이 동시에 돌면
    "There is no Stream(cpu, 0) in current thread" 크래시).
    모든 Whisper 호출은 이 래퍼를 거쳐 전역 락으로 직렬화한다.
    """
    import mlx_whisper
    from .ffbin import ensure_ffmpeg_on_path
    ensure_ffmpeg_on_path()  # whisper는 오디오 로드에 bare `ffmpeg`를 PATH에서 찾음
    with MLX_LOCK:
        return mlx_whisper.transcribe(wav_path, **kwargs)
