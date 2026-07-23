"""노이즈 제거 작업(비동기 세션) — 앱 계층.

동기 /api/denoise(브라우저가 몇 분씩 스피너만 보는 UX)를 대체:
- 백그라운드 처리 + 단계 진행 노출 (추출 → 노이즈 제거 → 블렌딩 → 재결합)
- 완료 시 원본/결과 미리듣기(A/B 비교)와 품질 리포트(발화 보존·무음 억제)
- 히스토리 보존 (결과 파일 + 미리듣기; 원본 미디어는 용량 절약을 위해
  미리듣기 추출 후 삭제)

영속 접근은 api.storage.store(어댑터)를 경유한다 (프로필·클로닝과 동일).
저장 위치·백엔드는 web/storage.py 참고.
"""
import os
import threading
import time
import uuid

from api import storage

_LOCK = threading.Lock()
DNJOBS = {}  # job_id → dict (메모리; 완료물은 meta.json으로 영구 저장)


def _persist(job, jdir=None):
    storage.store.write_doc("denoise", job["id"], job)


def start_denoise_job(file_storage, boost=0.0, mode="standard"):
    """업로드 파일 → 백그라운드 노이즈 제거 작업. → job_id

    mode="standard"(필터형 하이브리드) | "resynth"(생성형 재합성 —
    발화 중 노이즈까지 제거하되 목소리 유사도(SIM)를 함께 실측해 리포트).
    """
    from voxa.media.audio import default_output_ext, make_audio_preview, media_duration
    from voxa.denoise import (denoise_report, dfn_available, run_denoise,
                              voice_similarity)

    jid = uuid.uuid4().hex[:10]
    jdir = storage.store.entity_dir("denoise", jid)
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
           "started_ts": time.time(), "elapsed_sec": None, "eta_sec": None}
    with _LOCK:
        DNJOBS[jid] = job
        _persist(job, jdir)  # 시작 즉시 저장 — 새로고침해도 작업 센터에 보이게

    def on_progress(ev):
        with _LOCK:
            job["stage"] = ev.get("stage", job["stage"])
            _persist(job, jdir)

    def run():
        from api.rates import estimate_dn_eta, update_rate
        t0 = time.time()
        try:
            job["duration"] = media_duration(src)
            job["eta_sec"] = estimate_dn_eta(job["duration"], mode=mode)
            _persist(job, jdir)
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
            elapsed = time.time() - t0
            if job["duration"]:
                update_rate("dn_resynth" if mode == "resynth"
                            else "dn_standard",
                            max(elapsed - 10, 1) / job["duration"])
            job.update({"status": "done", "stage": "done",
                        "elapsed_sec": round(elapsed)})
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
    return storage.store.read_doc("denoise", jid)  # 서버 재시작 후


def dnjob_path(jid, kind):
    """kind: file(결과 다운로드) | orig(원본 미리듣기) | clean(결과 미리듣기)"""
    jdir = storage.store.entity_dir("denoise", jid, ensure=False)
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
    items = []
    for jid in storage.store.list_ids("denoise"):
        meta = storage.store.read_doc("denoise", jid)
        if meta is not None:
            items.append(meta)
    items.sort(key=lambda x: x.get("created", ""), reverse=True)
    return items[:limit]


_ACTIVE_STATUSES = ("running", "generating", "preparing", "queued")


def reconcile_interrupted():
    """서버 시작 시 비종료 상태로 남은 정리 작업을 '중단됨'으로 표시한다.
    새로 뜬 프로세스에는 진행 중인 작업이 있을 수 없으므로 안전하다. profiles의
    같은 함수와 짝을 이룬다. 정리한 개수를 돌려준다."""
    n = 0
    for jid in storage.store.list_ids("denoise"):
        meta = storage.store.read_doc("denoise", jid)
        if meta and meta.get("status") in _ACTIVE_STATUSES:
            meta["status"] = "error"
            meta["error"] = meta.get("error") or "interrupted"
            storage.store.write_doc("denoise", jid, meta)
            n += 1
    return n


STALE_SILENCE_SEC = 600


def reconcile_stale(silence=STALE_SILENCE_SEC):
    """세션 중 워치독(denoise용). 문서 mtime을 하트비트로, silence초 넘게 갱신이
    없는 비종료 작업을 멈춘 것으로 보고 오류 처리한다. profiles와 짝을 이룬다."""
    now = time.time()
    n = 0
    for jid in storage.store.list_ids("denoise"):
        meta = storage.store.read_doc("denoise", jid)
        if not meta or meta.get("status") not in _ACTIVE_STATUSES:
            continue
        mt = storage.store.doc_mtime("denoise", jid)
        if mt is not None and now - mt > silence:
            meta["status"] = "error"
            meta["error"] = meta.get("error") or "stuck (no progress)"
            storage.store.write_doc("denoise", jid, meta)
            n += 1
    return n


def delete_dnjob(jid):
    with _LOCK:
        DNJOBS.pop(jid, None)
    storage.store.delete_entity("denoise", jid)
