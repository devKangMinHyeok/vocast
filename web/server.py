#!/usr/bin/env python3
"""로컬 웹 서버 — 앱 계층.

이 파일은 HTTP(업로드/다운로드/에러 코드)만 다룬다.
노이즈 제거·클로닝의 실제 처리는 전부 core/ 가 한다 — ffmpeg·모델을
여기서 직접 만지지 않는다. (경계는 tests/test_architecture.py 가 강제)

실행:
  python3 web/server.py            # http://127.0.0.1:8756
  python3 web/server.py --port 9000
"""
import argparse
import os
import sys
import tempfile
import uuid

from flask import Flask, jsonify, request, send_file, send_from_directory

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from core.audio import default_output_ext, ensure_ffmpeg  # noqa: E402
from core.clone import clone_available, clone_voice  # noqa: E402
from core.denoise import run_denoise  # noqa: E402
from web import profiles  # noqa: E402

WORK = os.path.join(tempfile.gettempdir(), "denoise-app-work")
os.makedirs(WORK, exist_ok=True)

MEDIA_EXTS = {".mov", ".mp4", ".m4v", ".mkv", ".wav", ".m4a", ".mp3", ".aac"}
MAX_TEXT_LEN = 20000  # 장문 원고 지원 (문단 배치 파이프라인 — 약 40분 분량)

app = Flask(__name__)


@app.get("/")
def index():
    return send_from_directory(os.path.join(HERE, "static"), "index.html")


@app.get("/api/health")
def health():
    from core.denoise import dfn_available
    return jsonify(ok=True, denoise=True, clone=clone_available(),
                   denoise_engine="dfn-hybrid" if dfn_available() else "rnnoise")


def _save_upload(f):
    name, ext = os.path.splitext(os.path.basename(f.filename))
    ext = ext.lower()
    if ext not in MEDIA_EXTS:
        raise ValueError(f"지원하지 않는 형식입니다: {ext}")
    path = os.path.join(WORK, f"in_{uuid.uuid4().hex[:8]}{ext}")
    f.save(path)
    return path, name, ext


@app.post("/api/denoise")
def denoise_api():
    f = request.files.get("file")
    if not f or not f.filename:
        return jsonify(error="파일이 없습니다"), 400
    try:
        boost = float(request.form.get("boost") or 0)
    except ValueError:
        boost = 0.0
    try:
        in_path, name, ext = _save_upload(f)
    except ValueError as e:
        return jsonify(error=str(e)), 400

    out_ext = default_output_ext(ext)
    out_path = os.path.join(WORK, f"out_{uuid.uuid4().hex[:8]}{out_ext}")
    try:
        run_denoise(in_path, out_path, boost)
    except (RuntimeError, ValueError) as e:
        return jsonify(error=str(e)), 500
    finally:
        os.remove(in_path)
    return send_file(out_path, as_attachment=True,
                     download_name=f"{name}_clean{out_ext}")


@app.post("/api/clone")
def clone_api():
    """동기 클로닝 (구버전 호환 — CLI/스크립트용)."""
    if not clone_available():
        return jsonify(error="이 서버 환경에 mlx-audio가 설치되어 있지 않습니다. "
                             "pip install -r voice/requirements-voice.txt"), 501
    f = request.files.get("ref")
    text = (request.form.get("text") or "").strip()
    fast = request.form.get("fast") == "1"
    if not f or not f.filename:
        return jsonify(error="참조 목소리 파일이 없습니다"), 400
    if not text:
        return jsonify(error="읽어줄 대본이 비어 있습니다"), 400
    if len(text) > MAX_TEXT_LEN:
        return jsonify(error=f"대본이 너무 깁니다 ({MAX_TEXT_LEN}자 이내)"), 400
    try:
        ref_path, name, _ = _save_upload(f)
    except ValueError as e:
        return jsonify(error=str(e)), 400

    out_path = os.path.join(WORK, f"clone_{uuid.uuid4().hex[:8]}.wav")
    try:
        clone_voice(ref_path, text, out_path, fast=fast,
                    takes=1 if fast else 6)
    except RuntimeError as e:
        return jsonify(error=str(e)), 500
    finally:
        os.remove(ref_path)
    return send_file(out_path, as_attachment=True,
                     download_name=f"{name}_클론낭독.wav")


# ---- 가이드 녹음 / 보이스 프로필 ----

@app.get("/api/guide")
def guide_api():
    return jsonify(sentences=profiles.GUIDE_SENTENCES)


@app.get("/api/profiles")
def profiles_list_api():
    return jsonify(profiles=profiles.list_profiles())


@app.post("/api/profiles")
def profiles_create_api():
    name = (request.form.get("name") or request.json.get("name", "")
            if request.is_json else request.form.get("name", ""))
    return jsonify(profiles.create_profile(name or "내 목소리"))


@app.post("/api/profiles/<pid>/recordings")
def profiles_recording_api(pid):
    f = request.files.get("audio")
    if not f:
        return jsonify(error="녹음 파일이 없습니다"), 400
    try:
        return jsonify(profiles.add_recording(pid, f, request.form.get("idx", 0)))
    except FileNotFoundError:
        return jsonify(error="프로필이 없습니다"), 404


@app.post("/api/profiles/<pid>/sources")
def profiles_source_api(pid):
    f = request.files.get("audio")
    if not f:
        return jsonify(error="파일이 없습니다"), 400
    denoise = request.form.get("denoise", "1") != "0"
    try:
        return jsonify(profiles.add_source(pid, f, denoise=denoise))
    except FileNotFoundError:
        return jsonify(error="프로필이 없습니다"), 404


@app.post("/api/profiles/<pid>/build")
def profiles_build_api(pid):
    body = request.get_json(silent=True) or {}
    denoise = str(body.get("denoise", request.form.get("denoise", "1"))) != "0"
    try:
        return jsonify(profiles.build_profile(pid, denoise=denoise))
    except (RuntimeError, FileNotFoundError) as e:
        return jsonify(error=str(e)), 400


@app.delete("/api/profiles/<pid>")
def profiles_delete_api(pid):
    profiles.delete_profile(pid)
    return jsonify(ok=True)


# ---- 비동기 생성 작업 (진행 시각화 + 세션 저장) ----

@app.post("/api/jobs")
def jobs_create_api():
    if not clone_available():
        return jsonify(error="mlx-audio 미설치"), 501
    text = (request.form.get("text") or "").strip()
    fast = request.form.get("fast") == "1"
    profile_id = request.form.get("profile_id") or None
    if not text:
        return jsonify(error="읽어줄 대본이 비어 있습니다"), 400
    if len(text) > MAX_TEXT_LEN:
        return jsonify(error=f"대본이 너무 깁니다 ({MAX_TEXT_LEN}자 이내)"), 400

    ref_path = profile_name = None
    if profile_id:
        try:
            metas = {m["id"]: m for m in profiles.list_profiles()}
            profile_name = metas.get(profile_id, {}).get("name")
        except OSError:
            pass
    else:
        f = request.files.get("ref")
        if not f or not f.filename:
            return jsonify(error="참조 목소리 파일 또는 프로필이 필요합니다"), 400
        try:
            ref_path, _, _ = _save_upload(f)
        except ValueError as e:
            return jsonify(error=str(e)), 400

    takes = None
    if request.form.get("takes"):
        try:
            takes = min(8, max(1, int(request.form["takes"])))
        except ValueError:
            pass
    job_id = profiles.start_clone_job(text, fast, ref_path=ref_path,
                                      profile_id=profile_id,
                                      profile_name=profile_name,
                                      takes=takes,
                                      title=request.form.get("title") or None)
    return jsonify(job_id=job_id)


@app.post("/api/jobs/<job_id>/regen")
def jobs_regen_api(job_id):
    """문단 부분 재생성 → 새 버전 작업 (ElevenLabs Studio식 워크플로)."""
    if not clone_available():
        return jsonify(error="mlx-audio 미설치"), 501
    body = request.get_json(silent=True) or {}
    try:
        idx = int(body.get("paragraph", -1))
    except (TypeError, ValueError):
        return jsonify(error="문단 번호가 잘못됐습니다"), 400
    try:
        return jsonify(job_id=profiles.start_regen_job(job_id, idx))
    except ValueError as e:
        return jsonify(error=str(e)), 400


@app.get("/api/jobs/<job_id>")
def jobs_get_api(job_id):
    job = profiles.get_job(job_id)
    if not job:
        return jsonify(error="작업을 찾을 수 없습니다"), 404
    return jsonify(job)


@app.get("/api/jobs/<job_id>/audio")
def jobs_audio_api(job_id):
    p = profiles.job_output(job_id)
    if not p:
        return jsonify(error="결과가 아직 없습니다"), 404
    return send_file(p, as_attachment=False, download_name="클론낭독.wav")


@app.get("/api/history")
def history_api():
    return jsonify(items=profiles.list_history())


@app.patch("/api/history/<job_id>")
def history_rename_api(job_id):
    body = request.get_json(silent=True) or {}
    try:
        return jsonify(title=profiles.rename_history(job_id,
                                                     body.get("title", "")))
    except ValueError as e:
        return jsonify(error=str(e)), 400


@app.delete("/api/history/<job_id>")
def history_delete_api(job_id):
    profiles.delete_history(job_id)
    return jsonify(ok=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8756)
    args = ap.parse_args()
    ensure_ffmpeg()
    feats = "노이즈 제거" + (" + 보이스 클로닝" if clone_available() else
                            " (클로닝: 미설치 — voice/requirements-voice.txt)")
    print(f"노이즈 클리너 [{feats}] → http://127.0.0.1:{args.port}")
    app.run(host="127.0.0.1", port=args.port)


if __name__ == "__main__":
    main()
