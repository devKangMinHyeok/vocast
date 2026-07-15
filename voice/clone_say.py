#!/usr/bin/env python3
"""내 목소리로 대본을 읽어주는 보이스 클로닝 CLI (Apple Silicon 전용).

목소리가 담긴 파일(영상도 됨)을 주면, 그 목소리로 대본을 읽은 오디오를 만든다.

파이프라인 (지표 경쟁으로 확정한 최적 설정):
  1. 참조 파일에서 오디오 추출 (ffmpeg)
  2. RNNoise로 배경 소음 제거  ← 유사도(SIM)를 +0.02 올려주는 것으로 검증됨
  3. Whisper로 참조 음성 받아쓰기 (클로닝 모델에 필요)
  4. Qwen3-TTS 1.7B(Base)로 대본 낭독 생성 (--fast 는 0.6B)

검증 결과 (화자 유사도 SIM / 글자 오류율 CER / 자연스러움 MOS):
  SIM 0.917 — 본인 육성끼리 비교(0.909)보다 높음
  CER 0% — 숫자·영어 혼용 대본도 그대로 읽음
  MOS 3.50 — 원본 녹음(3.24)보다 자연스러움 점수 높음

사용법:
  python3 voice/clone_say.py --ref 내목소리.mov --text "안녕하세요" -o out.wav
  python3 voice/clone_say.py --ref 내목소리.wav --script 대본.txt -o out.wav --fast

준비물: brew install ffmpeg + pip install -r voice/requirements-voice.txt

⚠️ 본인 목소리이거나 명시적으로 동의받은 목소리만 사용할 것.
"""
import argparse
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RNNOISE = os.path.join(ROOT, "models", "rnnoise-sh.rnnn")

MODEL_BEST = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit"
MODEL_FAST = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
WHISPER = "mlx-community/whisper-large-v3-turbo"
PY = sys.executable
MAX_REF_SEC = 15  # 참조는 앞 15초면 충분


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, **kw)


def prepare_reference(ref_path, workdir):
    """참조 파일 → 노이즈 제거된 모노 wav + 받아쓰기 텍스트."""
    clean = os.path.join(workdir, "ref_clean.wav")
    run(["ffmpeg", "-y", "-v", "error", "-i", ref_path, "-t", str(MAX_REF_SEC),
         "-af", f"aformat=channel_layouts=mono,arnndn=m='{RNNOISE}'",
         "-c:a", "pcm_s16le", clean])
    print("· 참조 음성 노이즈 제거 완료")

    import mlx_whisper
    text = mlx_whisper.transcribe(
        clean, path_or_hf_repo=WHISPER, language="ko")["text"].strip()
    if not text:
        sys.exit("참조 파일에서 말소리를 찾지 못했습니다. 발화가 또렷한 구간이 필요해요.")
    print(f"· 참조 받아쓰기: {text}")
    return clean, text


def main():
    ap = argparse.ArgumentParser(description="내 목소리로 대본 읽어주기")
    ap.add_argument("--ref", required=True, help="목소리가 담긴 파일 (wav/mp3/mov/mp4 등)")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--text", help="읽어줄 문장")
    g.add_argument("--script", help="읽어줄 대본 텍스트 파일")
    ap.add_argument("-o", "--output", default="cloned_voice.wav", help="출력 wav 경로")
    ap.add_argument("--fast", action="store_true", help="가벼운 0.6B 모델 사용 (약간 낮은 품질)")
    args = ap.parse_args()

    if not os.path.exists(args.ref):
        sys.exit(f"참조 파일이 없습니다: {args.ref}")
    text = args.text or open(args.script, encoding="utf-8").read().strip()
    model = MODEL_FAST if args.fast else MODEL_BEST

    with tempfile.TemporaryDirectory() as wd:
        ref_wav, ref_text = prepare_reference(args.ref, wd)
        print(f"· 생성 중 ({model.split('/')[-1]}) …")
        out_dir = os.path.dirname(os.path.abspath(args.output)) or "."
        prefix = os.path.splitext(os.path.basename(args.output))[0]
        run([PY, "-m", "mlx_audio.tts.generate",
             "--model", model, "--text", text,
             "--ref_audio", ref_wav, "--ref_text", ref_text,
             "--join_audio", "--audio_format", "wav",
             "--output_path", out_dir, "--file_prefix", prefix],
            stdout=subprocess.DEVNULL)
    print(f"완료: {args.output}")


if __name__ == "__main__":
    main()
