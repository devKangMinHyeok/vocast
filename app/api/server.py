#!/usr/bin/env python3
"""로컬 웹 서버 — 앱 계층.

이 파일은 HTTP(업로드/다운로드/에러 코드)만 다룬다.
노이즈 제거·클로닝의 실제 처리는 전부 core/ 가 한다 — ffmpeg·모델을
여기서 직접 만지지 않는다. (경계는 tests/test_architecture.py 가 강제)

실행:
  python3 api/server.py            # http://127.0.0.1:8756
  python3 api/server.py --port 9000
"""
import argparse
import os
import sys
import tempfile
import uuid

from flask import Flask, jsonify, request, send_file, send_from_directory

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from voxa.media.audio import default_output_ext, ensure_ffmpeg  # noqa: E402
from voxa.clone import clone_available, clone_voice  # noqa: E402
from voxa.denoise import run_denoise  # noqa: E402
from api import dnjobs, profiles  # noqa: E402

WORK = os.path.join(tempfile.gettempdir(), "vocast-work")
os.makedirs(WORK, exist_ok=True)

MEDIA_EXTS = {".mov", ".mp4", ".m4v", ".mkv", ".wav", ".m4a", ".mp3", ".aac"}
MAX_TEXT_LEN = 20000  # 장문 원고 지원 (문단 배치 파이프라인 — 약 40분 분량)

app = Flask(__name__)


@app.get("/")
def index():
    return send_from_directory(os.path.join(HERE, "static"), "index.html")


@app.get("/api/health")
def health():
    import platform
    from voxa.denoise import dfn_available, resynth_available
    is_apple = platform.system() == "Darwin" and platform.machine() == "arm64"
    return jsonify(ok=True, denoise=True, clone=clone_available(),
                   denoise_engine="dfn-hybrid" if dfn_available() else "rnnoise",
                   resynth=resynth_available(),
                   platform=platform.system(), apple_silicon=is_apple)


@app.get("/api/models/status")
def models_status_api():
    from api import models as models_mod
    return jsonify(models_mod.status())


@app.post("/api/models/download")
def models_download_api():
    from api import models as models_mod
    body = request.get_json(silent=True) or {}
    started = models_mod.start_download(body.get("tier", "balanced"))
    return jsonify(ok=True, started=started)


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


# ---- 노이즈 제거 (비동기 작업 + A/B 미리듣기 + 품질 리포트) ----

@app.post("/api/dnjobs")
def dnjobs_create_api():
    f = request.files.get("file")
    if not f or not f.filename:
        return jsonify(error="파일이 없습니다"), 400
    ext = os.path.splitext(f.filename)[1].lower()
    if ext not in MEDIA_EXTS:
        return jsonify(error=f"지원하지 않는 형식입니다: {ext}"), 400
    try:
        boost = float(request.form.get("boost") or 0)
    except ValueError:
        boost = 0.0
    mode = request.form.get("mode") or "standard"
    if mode not in ("standard", "resynth"):
        return jsonify(error="mode는 standard 또는 resynth"), 400
    if mode == "resynth":
        from voxa.denoise import resynth_available
        if not resynth_available():
            return jsonify(error="재합성 엔진 미설치 — bash packaging/scripts/install_resynth.sh"), 501
    return jsonify(job_id=dnjobs.start_denoise_job(f, boost=boost, mode=mode))


@app.get("/api/dnjobs")
def dnjobs_list_api():
    return jsonify(items=dnjobs.list_dnjobs())


@app.get("/api/dnjobs/<jid>")
def dnjobs_get_api(jid):
    job = dnjobs.get_dnjob(jid)
    if not job:
        return jsonify(error="작업을 찾을 수 없습니다"), 404
    return jsonify(job)


@app.get("/api/dnjobs/<jid>/audio/<kind>")
def dnjobs_audio_api(jid, kind):
    if kind not in ("orig", "clean"):
        return jsonify(error="orig 또는 clean"), 400
    p = dnjobs.dnjob_path(jid, kind)
    if not p:
        return jsonify(error="미리듣기가 없습니다"), 404
    return send_file(p, mimetype="audio/mp4", conditional=True)


@app.get("/api/dnjobs/<jid>/file")
def dnjobs_file_api(jid):
    p = dnjobs.dnjob_path(jid, "file")
    job = dnjobs.get_dnjob(jid)
    if not p or not job:
        return jsonify(error="결과 파일이 없습니다"), 404
    return send_file(p, as_attachment=True, download_name=job["out_name"])


@app.delete("/api/dnjobs/<jid>")
def dnjobs_delete_api(jid):
    dnjobs.delete_dnjob(jid)
    return jsonify(ok=True)


@app.get("/api/rates")
def rates_api():
    """이 맥에서 실측된 처리 속도. UI가 속도를 추정으로 지어내지 않게 한다.

    clone_rtf 는 "출력 1초당 처리 초"라서 20이면 실시간보다 20배 느리다는 뜻이다.
    """
    from api.rates import get_rates
    return jsonify(get_rates())


@app.get("/api/profiles/<pid>/audio")
def profile_audio_api(pid):
    """프로필의 병합된 참조 음성. 앱이 실제 목소리 파형을 그릴 때 쓴다."""
    paths = profiles.profile_paths(pid)
    merged = os.path.join(profiles._profile_dir(pid), "merged.wav")
    if not os.path.exists(merged):
        if not paths:
            return jsonify(error="프로필 음성이 없습니다"), 404
        merged = paths[0]
    return send_file(merged, mimetype="audio/wav")


@app.get("/api/mcp/tools")
def mcp_tools_api():
    """MCP 서버가 에이전트에 실제로 노출하는 도구 목록.

    mcp_server 를 import 하면 FastMCP 가 딸려 오므로, 소스를 ast 로 읽어
    @mcp.tool() 붙은 함수의 이름과 docstring 첫 줄만 뽑는다. 목록이 코드와
    어긋날 수 없고(단일 소스), 서버 기동에 부작용도 없다.
    """
    import ast
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "mcp_server.py")
    items = []
    try:
        tree = ast.parse(open(path, encoding="utf-8").read())
    except (OSError, SyntaxError):
        return jsonify(items=[])
    for node in tree.body:
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        decorated = any(
            (isinstance(d, ast.Call) and getattr(d.func, "attr", "") == "tool")
            or getattr(d, "attr", "") == "tool"
            for d in node.decorator_list)
        if not decorated:
            continue
        doc = (ast.get_docstring(node) or "").strip().split("\n")[0]
        items.append({"name": node.name, "desc": doc})
    return jsonify(items=items)


# ---- 가이드 녹음 / 보이스 프로필 ----

@app.get("/api/guide")
def guide_api():
    """가이드 대본. lang 으로 언어를 고른다 (기본 한국어)."""
    lang = request.args.get("lang") or "ko"
    return jsonify(sentences=profiles.guide_sentences(lang), lang=lang)


@app.get("/api/profiles")
def profiles_list_api():
    return jsonify(profiles=profiles.list_profiles())


@app.post("/api/profiles")
def profiles_create_api():
    body = request.json if request.is_json else request.form
    name = (body.get("name") or "").strip()
    lang = body.get("lang") or "ko"
    return jsonify(profiles.create_profile(name or "내 목소리", lang=lang))


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
    """동기 빌드 (구버전 호환 — CLI/스크립트용)."""
    body = request.get_json(silent=True) or {}
    denoise = str(body.get("denoise", request.form.get("denoise", "1"))) != "0"
    try:
        return jsonify(profiles.build_profile(pid, denoise=denoise))
    except (RuntimeError, FileNotFoundError) as e:
        return jsonify(error=str(e)), 400


@app.post("/api/profiles/<pid>/build_async")
def profiles_build_async_api(pid):
    """비동기 빌드 — 작업 센터에서 추적 (웹 UI 기본 경로)."""
    body = request.get_json(silent=True) or {}
    denoise = str(body.get("denoise", "1")) != "0"
    try:
        return jsonify(job_id=profiles.start_build_job(pid, denoise=denoise))
    except FileNotFoundError:
        return jsonify(error="프로필이 없습니다"), 404


@app.post("/api/profiles/<pid>/rollback")
def profiles_rollback_api(pid):
    body = request.get_json(silent=True) or {}
    try:
        return jsonify(profiles.rollback_profile(pid, int(body.get("version"))))
    except (TypeError, ValueError) as e:
        return jsonify(error=str(e) or "버전 번호가 필요합니다"), 400
    except FileNotFoundError:
        return jsonify(error="프로필이 없습니다"), 404


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


@app.post("/api/jobs/<job_id>/perform")
def jobs_perform_api(job_id):
    """문단 연기 반영 재생성 — 사용자 녹음의 운율을 참조로 그 문단만 다시."""
    if not clone_available():
        return jsonify(error="mlx-audio 미설치"), 501
    f = request.files.get("audio")
    if not f:
        return jsonify(error="연기 녹음 파일이 없습니다"), 400
    try:
        idx = int(request.form.get("paragraph", -1))
    except (TypeError, ValueError):
        return jsonify(error="문단 번호가 잘못됐습니다"), 400
    denoise = request.form.get("denoise", "1") != "0"
    ext = os.path.splitext(f.filename or "rec.webm")[1] or ".webm"
    rec_path = os.path.join(WORK, f"perf_{uuid.uuid4().hex[:8]}{ext}")
    f.save(rec_path)
    try:
        return jsonify(job_id=profiles.start_performance_job(
            job_id, idx, rec_path, denoise=denoise))
    except ValueError as e:
        os.remove(rec_path)
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
    # The Studio library shows every saved narration, not just the most recent
    # handful, so this asks for a generous cap rather than the default 20.
    return jsonify(items=profiles.list_history(limit=500))


@app.get("/api/jobs/<job_id>/export")
def jobs_export_api(job_id):
    """완성 나레이션을 오디오로 내보낸다. format=wav|mp3, blocks=0,2,3(문단 선택)."""
    fmt = (request.args.get("format") or "wav").lower()
    blocks = None
    if request.args.get("blocks"):
        try:
            blocks = [int(x) for x in request.args["blocks"].split(",") if x.strip()]
        except ValueError:
            return jsonify(error="블록 번호가 잘못됐어요"), 400
    try:
        path = profiles.export_audio(job_id, fmt, blocks)
    except ValueError as e:
        return jsonify(error=str(e)), 400
    mime = "audio/mpeg" if fmt == "mp3" else "audio/wav"
    return send_file(path, as_attachment=False,
                     download_name=f"narration.{fmt}", mimetype=mime)


@app.post("/api/history/<job_id>/duplicate")
def history_duplicate_api(job_id):
    body = request.get_json(silent=True) or {}
    try:
        return jsonify(id=profiles.duplicate_history(job_id, body.get("title")))
    except ValueError as e:
        return jsonify(error=str(e)), 400


@app.post("/api/history/import")
def history_import_api():
    """.vocast 번들 가져오기: manifest(폼 필드) + audio(output.wav 파일)."""
    import json as _json
    f = request.files.get("audio")
    manifest_raw = request.form.get("manifest")
    if not f or not manifest_raw:
        return jsonify(error="프로젝트 파일이 불완전해요"), 400
    try:
        manifest = _json.loads(manifest_raw)
    except ValueError:
        return jsonify(error="잘못된 프로젝트 파일이에요"), 400
    tmp = os.path.join(WORK, f"imp_{uuid.uuid4().hex[:8]}.wav")
    f.save(tmp)
    try:
        new_id = profiles.import_history(manifest, tmp)
    except ValueError as e:
        return jsonify(error=str(e)), 400
    finally:
        try:
            os.remove(tmp)
        except OSError:
            pass
    return jsonify(id=new_id)


@app.get("/api/tasks")
def tasks_api():
    """작업 센터: 모든 비동기 작업(클로닝·노이즈 제거·프로필 분석) 한눈에."""
    fields = ("id", "kind", "title", "status", "stage", "created",
              "started_ts", "eta_sec", "elapsed_sec", "error", "pns", "mode")
    items = []
    for j in profiles.list_history(limit=25):
        t = {k: j.get(k) for k in fields}
        t["kind"] = j.get("kind") or "clone"
        items.append(t)
    for j in dnjobs.list_dnjobs(limit=15):
        t = {k: j.get(k) for k in fields}
        t["kind"] = "denoise"
        items.append(t)
    active = ("running", "generating", "preparing")
    items.sort(key=lambda x: x.get("created") or "", reverse=True)
    items.sort(key=lambda x: x["status"] not in active)  # 진행 중 먼저 (안정 정렬)
    return jsonify(items=items[:30])


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


def _install_parent_watchdog():
    """부모(맥 앱)가 죽으면 서버도 스스로 종료 — 사이드카 고아 프로세스 방지.

    macOS엔 리눅스의 PR_SET_PDEATHSIG가 없어 부모 PID를 폴링한다. VOCAST_PARENT_PID
    가 있을 때만 동작하므로 웹/CLI 단독 실행에는 영향이 없다.
    """
    pid_s = os.environ.get("VOCAST_PARENT_PID")
    if not pid_s:
        return
    try:
        ppid = int(pid_s)
    except ValueError:
        return
    import threading
    import time

    def _watch():
        while True:
            time.sleep(1.0)
            try:
                os.kill(ppid, 0)  # 존재 확인 (신호 안 보냄)
            except OSError:
                os._exit(0)       # 부모 사라짐 → 하드 종료

    threading.Thread(target=_watch, daemon=True).start()


def _start_stale_watchdog(interval=60):
    """세션 중 멈춘 작업 감지. 시작 시 정리(reconcile_interrupted)는 재시작 케이스만
    커버하므로, 엔진이 오래 돌 때 워커가 죽어 멈춘 작업을 주기적으로 잡는다.
    데몬 스레드라 서버 종료를 막지 않는다."""
    import threading
    import time

    def _sweep():
        while True:
            time.sleep(interval)
            try:
                n = profiles.reconcile_stale() + dnjobs.reconcile_stale()
                if n:
                    print(f"워치독: 멈춘 작업 {n}건을 오류로 표시")
            except Exception:
                pass  # 스윕 실패가 서버를 죽이지 않게

    threading.Thread(target=_sweep, daemon=True).start()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8756)
    args = ap.parse_args()
    _install_parent_watchdog()
    # 이전 실행이 남긴 유령 작업(진행 중인 채로 죽은 것)을 정리한다. 새로 뜬
    # 서버엔 진행 중인 작업이 있을 수 없으므로, 남아 있으면 중단된 것이다.
    stale = profiles.reconcile_interrupted() + dnjobs.reconcile_interrupted()
    if stale:
        print(f"정리: 중단된 작업 {stale}건을 오류로 표시")
    _start_stale_watchdog()
    ensure_ffmpeg()
    feats = "노이즈 제거" + (" + 보이스 클로닝" if clone_available() else
                            " (클로닝: 미설치 — voice/requirements-voice.txt)")
    print(f"Vocast [{feats}] → http://127.0.0.1:{args.port}")
    app.run(host="127.0.0.1", port=args.port)


if __name__ == "__main__":
    main()
