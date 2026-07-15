#!/usr/bin/env python3
"""영상/음성 배경 소음 제거 CLI.

목소리는 그대로 두고 배경 소음(백색소음, 팬 소리 등)만 제거한 새 파일을 만든다.
원본 파일은 절대 수정하지 않는다.

원리: RNNoise — 사람 목소리만 남기도록 학습된 신경망 모델을 ffmpeg(arnndn 필터)으로 통과시킨다.

사용법:
  python3 denoise.py input.mov                # → input_clean.mov
  python3 denoise.py input.mov -o output.mov  # 출력 이름 지정
  python3 denoise.py input.mov --boost 13     # 볼륨도 13dB 키우기
"""
import argparse
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = os.path.join(HERE, "models", "rnnoise-sh.rnnn")

VIDEO_EXTS = {".mov", ".mp4", ".m4v", ".mkv"}


def has_video_stream(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries",
         "stream=codec_type", "-of", "csv=p=0", path],
        capture_output=True, text=True)
    return "video" in out.stdout


def build_audio_filter(boost=0.0):
    af = f"aformat=channel_layouts=mono,arnndn=m='{MODEL}'"
    if boost:
        af += f",volume={boost}dB"
    return af


def run_denoise(input_path, output_path, boost=0.0):
    cmd = ["ffmpeg", "-y", "-v", "error", "-i", input_path]
    if has_video_stream(input_path):
        cmd += ["-c:v", "copy"]  # 영상 화질은 재압축 없이 그대로 복사
    cmd += ["-af", build_audio_filter(boost)]
    ext = os.path.splitext(output_path)[1].lower()
    if ext == ".wav":
        cmd += ["-c:a", "pcm_s16le"]
    else:
        cmd += ["-c:a", "aac", "-b:a", "192k"]
    cmd.append(output_path)
    subprocess.run(cmd, check=True)


def main():
    ap = argparse.ArgumentParser(description="영상/음성 배경 소음 제거")
    ap.add_argument("input", help="입력 파일 (mov, mp4, wav, m4a 등)")
    ap.add_argument("-o", "--output", help="출력 파일 경로 (기본: 입력이름_clean.확장자)")
    ap.add_argument("--boost", type=float, default=0.0,
                    help="노이즈 제거 후 볼륨을 N dB 키움 (기본 0)")
    args = ap.parse_args()

    if not shutil.which("ffmpeg"):
        sys.exit("ffmpeg이 필요합니다. 설치: brew install ffmpeg")
    if not os.path.exists(args.input):
        sys.exit(f"입력 파일이 없습니다: {args.input}")
    if not os.path.exists(MODEL):
        sys.exit(f"모델 파일이 없습니다: {MODEL}")

    base, ext = os.path.splitext(args.input)
    out = args.output or f"{base}_clean{ext or '.mov'}"
    if os.path.abspath(out) == os.path.abspath(args.input):
        sys.exit("출력이 입력과 같은 파일입니다. 원본 보호를 위해 중단합니다.")

    print("처리 중...", os.path.basename(args.input), "→", os.path.basename(out))
    run_denoise(args.input, out, args.boost)
    print("완료:", out)


if __name__ == "__main__":
    main()
