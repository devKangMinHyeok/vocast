#!/usr/bin/env python3
"""내 목소리로 대본을 읽어주는 보이스 클로닝 CLI. (핵심 로직은 core/clone.py)

사용법:
  python3 voice/clone_say.py --ref 내목소리.mov --text "안녕하세요" -o out.wav
  python3 voice/clone_say.py --ref 내목소리.wav --script 대본.txt -o out.wav --fast

준비물: brew install ffmpeg + pip install -r voice/requirements-voice.txt (Apple Silicon)

⚠️ 본인 목소리이거나 명시적으로 동의받은 목소리만 사용할 것.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from core.audio import ensure_ffmpeg  # noqa: E402
from core.clone import clone_available, clone_voice  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description="내 목소리로 대본 읽어주기")
    ap.add_argument("--ref", required=True, help="목소리가 담긴 파일 (wav/mp3/mov/mp4 등)")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--text", help="읽어줄 문장")
    g.add_argument("--script", help="읽어줄 대본 텍스트 파일")
    ap.add_argument("-o", "--output", default="cloned_voice.wav", help="출력 wav 경로")
    ap.add_argument("--fast", action="store_true", help="가벼운 0.6B 모델 사용 (약간 낮은 품질)")
    ap.add_argument("--takes", type=int, default=4,
                    help="테이크 수 — 여러 번 생성해 운율 점수(PNS) 최고를 채택 (기본 4, 1=최속)")
    args = ap.parse_args()

    try:
        ensure_ffmpeg()
    except RuntimeError as e:
        sys.exit(str(e))
    if not clone_available():
        sys.exit("mlx-audio가 없습니다. 설치: pip install -r voice/requirements-voice.txt")
    if not os.path.exists(args.ref):
        sys.exit(f"참조 파일이 없습니다: {args.ref}")

    text = args.text or open(args.script, encoding="utf-8").read().strip()
    print("· 참조 음성 준비 중 (노이즈 제거 + 참조 창 자동 선택 + 받아쓰기)…")
    try:
        clone_voice(args.ref, text, args.output, fast=args.fast, takes=args.takes)
    except RuntimeError as e:
        sys.exit(str(e))
    print(f"완료: {args.output}")


if __name__ == "__main__":
    main()
