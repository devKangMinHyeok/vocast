"""노이즈 제거 작업(비동기 세션) — 앱 계층.

동기 /api/denoise(브라우저가 몇 분씩 스피너만 보는 UX)를 대체:
- 백그라운드 처리 + 단계 진행 노출 (추출 → 노이즈 제거 → 블렌딩 → 재결합)
- 완료 시 원본/결과 미리듣기(A/B 비교)와 품질 리포트(발화 보존·무음 억제)
- 히스토리 보존 (결과 파일 + 미리듣기; 원본 미디어는 용량 절약을 위해
  미리듣기 추출 후 삭제)

저장 위치: ~/.noisecleaner/denoise/<job>/ (프로필·클로닝과 같은 HOME)
"""
import json
import os
import shutil
import threading
import time
import uuid

from web.profiles import HOME

DN_DIR = os.path.join(HOME, "denoise")
_LOCK = threading.Lock()
DNJOBS = {}  # job_id → dict (메모리; 완료물은 meta.json으로 영구 저장)


def _persist(job, jdir):
    with open(os.path.join(jdir, "meta.json"), "w", encoding="utf-8") as f:
        json.dump(job, f, ensure_ascii=False, indent=2)


def start_denoise_job(file_storage, boost=0.0, mode="standard"):
    """업로드 파일 → 백그라운드 노이즈 제거 작업. → job_id

    mode="standard"(필터형 하이브리드) | "resynth"(생성형 재합성 —
    발화 중 노이즈까지 제거하되 목소리 유사도(SIM)를 함께 실측해 리포트).
    """
    from core.audio import default_output_ext, make_audio_preview, media_duration
    from core.denoise import (denoise_report, dfn_available, run_denoise,
                              voice_similarity)

    os.makedirs(DN_DIR, exist_ok=True)
    jid = uuid.uuid4().hex[:10]
    jdir = os.path.join(DN_DIR, jid)
    os.makedirs(jdir)
    name = os.path.basename(file_storage.filename or "input.wav")
    base, ext = os.path.splitext(name)
    ext = ext.lower() or ".wav"
    src = os.path.join(jdir, "original" + ext)
    file_storage.save(src)
    out_ext = default_output_ext(ext)
    out = os.path.join(jdir, "clean" + out_ext)

    job = {"id": jid, "status": "running", "stage": "extract",
           "title": name, "out_name": f"{base}_clean{out_ext}",
           "boost": float(boost), "mode": mode,
           "engine": ("resynth" if mode == "resynth"
                      else "dfn-hybrid" if dfn_available() else "rnnoise"),
           "size_mb": round(os.path.getsize(src) / 1e6, 1),
           "duration": None, "report": None, "error": None,
           "created": time.strftime("%Y-%m-%d %H:%M"),
           "started_ts": time.time(), "elapsed_sec": None}
    with _LOCK:
        DNJOBS[jid] = job

    def on_progress(ev):
        with _LOCK:
            job["stage"] = ev.get("stage", job["stage"])

    def run():
        t0 = time.time()
        try:
            job["duration"] = media_duration(src)
            run_denoise(src, out, boost=boost, mode=mode,
                        on_progress=on_progress)
            job["stage"] = "preview"
            make_audio_preview(src, os.path.join(jdir, "orig.m4a"))
            make_audio_preview(out, os.path.join(jdir, "clean.m4a"))
            job["stage"] = "report"
            if mode == "resynth":
                # 프레임 단위 손실 지표는 재생성 오디오에 무효 (실측:
                # 손실 12.7%로 떴지만 받아쓰기는 95.7% 일치 — 에너지 윤곽을
                # 새로 그려서 생기는 착시) → 재합성은 SIM만 리포트
                job["report"] = {"sim": voice_similarity(src, out)}
            else:
                job["report"] = denoise_report(src, out)
            job.update({"status": "done", "stage": "done",
                        "elapsed_sec": round(time.time() - t0)})
        except Exception as e:
            job.update({"status": "error", "error": str(e)[-300:]})
        finally:
            if os.path.exists(src):  # 원본은 미리듣기 추출 후 삭제 (용량)
                os.remove(src)
            _persist(job, jdir)

    threading.Thread(target=run, daemon=True).start()
    return jid


def get_dnjob(jid):
    with _LOCK:
        if jid in DNJOBS:
            return dict(DNJOBS[jid])
    meta = os.path.join(DN_DIR, jid, "meta.json")  # 서버 재시작 후
    if os.path.exists(meta):
        with open(meta, encoding="utf-8") as f:
            return json.load(f)
    return None


def dnjob_path(jid, kind):
    """kind: file(결과 다운로드) | orig(원본 미리듣기) | clean(결과 미리듣기)"""
    jdir = os.path.join(DN_DIR, jid)
    if kind == "orig":
        p = os.path.join(jdir, "orig.m4a")
    elif kind == "clean":
        p = os.path.join(jdir, "clean.m4a")
    else:
        job = get_dnjob(jid)
        if not job:
            return None
        ext = os.path.splitext(job.get("out_name", ".wav"))[1]
        p = os.path.join(jdir, "clean" + ext)
    return p if os.path.exists(p) else None


def list_dnjobs(limit=20):
    if not os.path.isdir(DN_DIR):
        return []
    items = []
    for jid in os.listdir(DN_DIR):
        meta = os.path.join(DN_DIR, jid, "meta.json")
        if os.path.exists(meta):
            try:
                with open(meta, encoding="utf-8") as f:
                    items.append(json.load(f))
            except (OSError, json.JSONDecodeError):
                continue
    items.sort(key=lambda x: x.get("created", ""), reverse=True)
    return items[:limit]


def delete_dnjob(jid):
    with _LOCK:
        DNJOBS.pop(jid, None)
    shutil.rmtree(os.path.join(DN_DIR, jid), ignore_errors=True)
