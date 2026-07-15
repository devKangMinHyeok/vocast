#!/usr/bin/env python3
"""로컬 노이즈 제거 웹 서버.

브라우저에서 파일을 올리면 노이즈를 제거해 돌려준다. 모든 처리는 이 컴퓨터
안에서만 일어나고, 파일이 외부로 전송되지 않는다.

실행:
  python3 web/server.py            # http://127.0.0.1:8756
  python3 web/server.py --port 9000
"""
import argparse
import os
import subprocess
import sys
import tempfile
import uuid

from flask import Flask, jsonify, request, send_file, send_from_directory

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)
from denoise import build_audio_filter, has_video_stream, MODEL  # noqa: E402

WORK = os.path.join(tempfile.gettempdir(), "denoise-app-work")
os.makedirs(WORK, exist_ok=True)

ALLOWED_EXTS = {".mov", ".mp4", ".m4v", ".mkv", ".wav", ".m4a", ".mp3", ".aac"}

app = Flask(__name__)


@app.get("/")
def index():
    return send_from_directory(os.path.join(HERE, "static"), "index.html")


@app.get("/api/health")
def health():
    return jsonify(ok=True)


@app.post("/api/denoise")
def denoise_api():
    f = request.files.get("file")
    if not f or not f.filename:
        return jsonify(error="파일이 없습니다"), 400
    try:
        boost = float(request.form.get("boost") or 0)
    except ValueError:
        boost = 0.0

    name, ext = os.path.splitext(os.path.basename(f.filename))
    ext = ext.lower()
    if ext not in ALLOWED_EXTS:
        return jsonify(error=f"지원하지 않는 형식입니다: {ext}"), 400

    uid = uuid.uuid4().hex[:8]
    in_path = os.path.join(WORK, f"in_{uid}{ext}")
    out_ext = ext if ext != ".mp3" else ".m4a"  # mp3 재인코딩 대신 m4a로
    out_path = os.path.join(WORK, f"out_{uid}{out_ext}")
    f.save(in_path)

    cmd = ["ffmpeg", "-y", "-v", "error", "-i", in_path]
    if has_video_stream(in_path):
        cmd += ["-c:v", "copy"]
    cmd += ["-af", build_audio_filter(boost)]
    if out_ext == ".wav":
        cmd += ["-c:a", "pcm_s16le"]
    else:
        cmd += ["-c:a", "aac", "-b:a", "192k"]
    cmd.append(out_path)

    proc = subprocess.run(cmd, capture_output=True, text=True)
    os.remove(in_path)
    if proc.returncode != 0 or not os.path.exists(out_path):
        return jsonify(error="변환 실패: " + proc.stderr[-300:]), 500

    return send_file(out_path, as_attachment=True,
                     download_name=f"{name}_clean{out_ext}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8756)
    args = ap.parse_args()
    if not os.path.exists(MODEL):
        sys.exit(f"모델 파일이 없습니다: {MODEL}")
    print(f"노이즈 클리너 실행 중 → http://127.0.0.1:{args.port}")
    app.run(host="127.0.0.1", port=args.port)


if __name__ == "__main__":
    main()
