"""보이스 프로필 + 생성 작업(세션) 관리 — 앱 계층.

- 프로필: 가이드 문장 녹음들 → 병합·분석해 참조 자산(창/받아쓰기/자연 통계)을
  캐시. 한 번 만들면 이후 생성마다 참조 준비(노이즈 제거+받아쓰기+분석)를
  건너뛴다.
- 작업(job): 생성을 백그라운드 스레드로 돌리고 진행 상황(테이크 오디션 점수)을
  실시간 노출. 완료물은 히스토리로 영구 저장 — 세션 분리·보관.

저장 위치: ~/.noisecleaner/{profiles,history}/ (환경변수 NOISECLEANER_HOME으로 변경 가능)
"""
import json
import os
import shutil
import threading
import time
import uuid

HOME = os.environ.get("NOISECLEANER_HOME",
                      os.path.expanduser("~/.noisecleaner"))
PROFILES_DIR = os.path.join(HOME, "profiles")
HISTORY_DIR = os.path.join(HOME, "history")

# 가이드 문장: 지표로 검증된 결함 차원(끝음 유형·억양 역동성·호흡·속도·강세)을
# 고루 커버하도록 설계. 전체 낭독 약 90초.
GUIDE_SENTENCES = [
    {"text": "안녕하세요! 제 목소리로 말하는 첫 번째 문장입니다.",
     "tip": "평소 인사하듯 밝고 자연스럽게", "focus": "인사 톤"},
    {"text": "오늘은 날씨가 맑고, 바람도 적당히 불어서 산책하기 좋은 날이에요.",
     "tip": "쉼표에서 살짝 숨을 쉬어주세요", "focus": "평서문·호흡"},
    {"text": "그런데 혹시, 이 기능이 어떻게 작동하는지 궁금하지 않으세요?",
     "tip": "끝을 자연스럽게 올려주세요", "focus": "의문문 끝음"},
    {"text": "와, 이건 정말 놀라운 결과인데요! 기대 이상이에요.",
     "tip": "진짜 놀란 것처럼 감정을 실어서", "focus": "감탄·강조"},
    {"text": "2026년 7월 기준으로, AI 모델은 5분 만에 학습을 마칩니다.",
     "tip": "숫자와 영어를 또렷하게", "focus": "숫자·영어"},
    {"text": "노이즈를 제거하고, 목소리를 학습하고, 문장을 읽어주는 것까지, 전부 자동입니다.",
     "tip": "리듬감 있게, 쉼표마다 잠깐씩", "focus": "긴 문장 리듬"},
    {"text": "자, 지금부터 진짜 중요한 부분이니까 집중해서 봐주세요!",
     "tip": "에너지 있게, 조금 빠르게", "focus": "빠른 호흡"},
    {"text": "천천히, 하나씩, 차근차근 설명해 드릴게요.",
     "tip": "일부러 느리고 차분하게", "focus": "느린 호흡"},
    {"text": "친구가 '이거 진짜 네 목소리 맞아?'라고 물어볼 정도였어요.",
     "tip": "인용 부분은 말투를 살짝 바꿔서", "focus": "대화체"},
    {"text": "지금까지 들어주셔서 감사합니다. 다음 영상에서 또 만나요.",
     "tip": "마무리답게 끝을 부드럽게 내려주세요", "focus": "마무리 끝음"},
]

_LOCK = threading.Lock()
JOBS = {}  # job_id → dict (메모리; 완료물은 히스토리에 영구 저장)


def _ensure_dirs():
    os.makedirs(PROFILES_DIR, exist_ok=True)
    os.makedirs(HISTORY_DIR, exist_ok=True)


def _meta_path(pid):
    return os.path.join(PROFILES_DIR, pid, "meta.json")


def _load_meta(pid):
    with open(_meta_path(pid), encoding="utf-8") as f:
        return json.load(f)


def _save_meta(pid, meta):
    with open(_meta_path(pid), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)


def create_profile(name):
    _ensure_dirs()
    pid = uuid.uuid4().hex[:10]
    os.makedirs(os.path.join(PROFILES_DIR, pid, "raw"), exist_ok=True)
    meta = {"id": pid, "name": name.strip() or "내 목소리",
            "created": time.strftime("%Y-%m-%d %H:%M"),
            "recordings": 0, "ready": False, "stats": None}
    _save_meta(pid, meta)
    return meta


def add_recording(pid, file_storage, idx):
    raw = os.path.join(PROFILES_DIR, pid, "raw")
    ext = os.path.splitext(file_storage.filename or "r.webm")[1] or ".webm"
    file_storage.save(os.path.join(raw, f"{int(idx):02d}{ext}"))
    meta = _load_meta(pid)
    meta["recordings"] = len(os.listdir(raw))
    _save_meta(pid, meta)
    return meta


def add_source(pid, file_storage, denoise=True):
    """추가 소스(기존 음성/영상 파일) 등록 — 소스별 노이즈 제거 플래그 저장."""
    sdir = os.path.join(PROFILES_DIR, pid, "sources")
    os.makedirs(sdir, exist_ok=True)
    ext = os.path.splitext(file_storage.filename or "s.wav")[1] or ".wav"
    fname = f"{uuid.uuid4().hex[:8]}{ext}"
    file_storage.save(os.path.join(sdir, fname))
    meta = _load_meta(pid)
    meta.setdefault("sources", []).append({
        "file": fname, "name": file_storage.filename,
        "denoise": bool(denoise)})
    _save_meta(pid, meta)
    return meta


def build_profile(pid, denoise=True):
    """소스 전처리(개별 노이즈 제거) → 병합 → 참조 자산 캐시 → 통계 분석.

    입력 = 가이드 녹음(일괄 denoise 플래그) + 추가 소스(소스별 플래그).
    각자 플래그대로 전처리한 뒤 병합하므로, 이후 단계는 재차 제거하지 않는다.
    """
    from core.audio import concat_to_wav
    from core.clone import prepare_reference
    from core.denoise import preprocess_source
    from core.prosody import (final_f0_slopes, prosody_features,
                              stress_features)

    pdir = os.path.join(PROFILES_DIR, pid)
    meta = _load_meta(pid)
    raw = os.path.join(pdir, "raw")
    guided = (sorted(os.path.join(raw, f) for f in os.listdir(raw)
                     if not f.startswith(".")) if os.path.isdir(raw) else [])
    sources = meta.get("sources", [])
    if not guided and not sources:
        raise RuntimeError("녹음이나 소스 파일이 없습니다")

    prep_dir = os.path.join(pdir, "prep")
    shutil.rmtree(prep_dir, ignore_errors=True)
    os.makedirs(prep_dir)
    prepped = []
    for i, f in enumerate(guided):  # 가이드 녹음: 일괄 플래그
        prepped.append(preprocess_source(
            f, os.path.join(prep_dir, f"g{i:02d}.wav"), denoise=denoise))
    for i, s in enumerate(sources):  # 추가 소스: 소스별 플래그
        prepped.append(preprocess_source(
            os.path.join(pdir, "sources", s["file"]),
            os.path.join(prep_dir, f"s{i:02d}.wav"),
            denoise=s.get("denoise", True)))

    merged = os.path.join(pdir, "merged.wav")
    concat_to_wav(prepped, merged)
    ref_wav, ref_text, natural = prepare_reference(merged, pdir,
                                                   denoise=False)

    feats = prosody_features(natural)
    stress = stress_features(natural) or {}
    slopes = final_f0_slopes(natural)
    meta.update({
        "ready": True,
        "denoised": bool(denoise),
        "ref_wav": os.path.basename(ref_wav),
        "ref_text": ref_text,
        "natural_wav": os.path.basename(natural),
        "stats": {
            "duration": round(feats["duration"], 1),
            "f0_std": round(feats["f0_st_std"], 2),      # 억양 역동성 (st)
            "rate": round(feats["artic_rate"], 1),        # 말 속도 (음절/s)
            "pause_rate": round(feats["pause_rate"], 2),  # 호흡 빈도 (/s)
            "peak_range": round(stress.get("peak_range", 0), 1),  # 강세 구조
            "ending": round(float(sum(slopes) / len(slopes)), 1) if slopes else 0,
        }})
    _save_meta(pid, meta)
    return meta


def list_profiles():
    _ensure_dirs()
    out = []
    for pid in sorted(os.listdir(PROFILES_DIR)):
        try:
            out.append(_load_meta(pid))
        except (OSError, json.JSONDecodeError):
            continue
    return out


def delete_profile(pid):
    shutil.rmtree(os.path.join(PROFILES_DIR, pid), ignore_errors=True)


def profile_paths(pid):
    """캐시된 참조 자산 → (ref_wav, ref_text, natural_wav). 미완성이면 None."""
    meta = _load_meta(pid)
    if not meta.get("ready"):
        return None
    pdir = os.path.join(PROFILES_DIR, pid)
    return (os.path.join(pdir, meta["ref_wav"]), meta["ref_text"],
            os.path.join(pdir, meta["natural_wav"]))


# ---- 생성 작업 (비동기 세션) ----

def _new_job(job_id, text, profile_name, profile_id, settings,
             title=None, parent=None, version=1):
    """작업 레코드 공통 골격 — 라이브러리 카드·버전 계보·이어서 작업의 재료."""
    return {"id": job_id, "status": "preparing", "stage": "reference",
            "takes": [], "composed": [], "paragraphs": None,
            "text": text, "profile": profile_name, "profile_id": profile_id,
            "title": (title or text.strip().replace("\n", " ")[:24]).strip(),
            "settings": settings, "version": version, "parent": parent,
            "created": time.strftime("%Y-%m-%d %H:%M"),
            "started_ts": time.time(), "error": None, "pns": None}


def _make_progress(job):
    """코어 진행 이벤트 → 작업 레코드 반영 (파이프라인 가시성의 데이터원)."""
    def on_progress(ev):
        with _LOCK:
            s = ev.get("stage")
            if s == "reference_done":
                job["status"] = "generating"
                job["stage"] = "takes"
            elif s == "paragraph":
                job["paragraph"] = {"i": ev["i"], "n": ev["n"]}
            elif s == "take":
                job["stage"] = f"take {ev['i']}/{ev['n']}"
            elif s == "take_scored":
                job["takes"].append(ev)
            elif s == "composed":
                job["composed"].append(ev.get("takes"))
            elif s == "done":
                job["stage"] = "post"
                if ev.get("pns") is not None:
                    job["final_pns"] = ev["pns"]
                if ev.get("paragraphs"):
                    job["paragraphs"] = ev["paragraphs"]
    return on_progress


def _finish_job(job, out, t_start):
    picked = max(job["takes"], key=lambda t: t.get("sel", -1e9), default=None)
    elapsed = time.time() - t_start
    rtf = None
    try:  # 처리량 북극성: RTF = 처리 시간 / 오디오 길이
        import soundfile as sf
        rtf = round(elapsed / max(sf.info(out).duration, 0.1), 1)
    except Exception:
        pass
    job.update({"status": "done", "stage": "done",
                "pns": job.pop("final_pns", None)
                or (picked.get("pns") if picked else None),
                "elapsed_sec": round(elapsed), "rtf": rtf})


def _persist_job(job, jdir):
    with open(os.path.join(jdir, "meta.json"), "w", encoding="utf-8") as f:
        json.dump(job, f, ensure_ascii=False, indent=2)


def start_clone_job(text, fast, ref_path=None, profile_id=None,
                    profile_name=None, takes=None, title=None):
    """백그라운드 생성 작업 시작 → job_id. 진행은 JOBS[job_id]에 기록."""
    from core.clone import DEFAULT_TAKES, clone_voice, synthesize_best

    _ensure_dirs()
    job_id = uuid.uuid4().hex[:10]
    n_takes = takes or (1 if fast else DEFAULT_TAKES)
    job = _new_job(job_id, text, profile_name, profile_id,
                   {"fast": bool(fast), "takes": n_takes}, title=title)
    with _LOCK:
        JOBS[job_id] = job
    on_progress = _make_progress(job)

    def run():
        jdir = os.path.join(HISTORY_DIR, job_id)
        os.makedirs(jdir, exist_ok=True)
        out = os.path.join(jdir, "output.wav")
        t_start = time.time()
        try:
            if profile_id:
                paths = profile_paths(profile_id)
                if not paths:
                    raise RuntimeError("프로필이 아직 준비되지 않았습니다")
                job["status"] = "generating"
                synthesize_best(text, paths[0], paths[1], paths[2], out,
                                fast=fast, takes=n_takes,
                                on_progress=on_progress)
            else:
                clone_voice(ref_path, text, out, fast=fast, takes=n_takes,
                            on_progress=on_progress)
            _finish_job(job, out, t_start)
        except Exception as e:  # 실패도 세션에 기록
            job.update({"status": "error", "error": str(e)[-300:]})
        finally:
            if ref_path and os.path.exists(ref_path):
                os.remove(ref_path)
            _persist_job(job, jdir)

    threading.Thread(target=run, daemon=True).start()
    return job_id


def start_regen_job(parent_id, index):
    """완성 작업에서 문단 하나만 다시 생성한 새 버전(v+1) 작업 시작.

    ElevenLabs Studio식 부분 재생성 — 전체를 다시 만들지 않고 마음에 안 드는
    문단만 교체. 프로필 기반 작업만 지원(업로드 참조는 작업 후 삭제되므로).
    """
    from core.clone import DEFAULT_TAKES, regenerate_paragraph

    parent = get_job(parent_id)
    if not parent or parent.get("status") != "done":
        raise ValueError("완성된 작업이 아닙니다")
    paras = parent.get("paragraphs")
    if not paras or not (0 <= index < len(paras)):
        raise ValueError("문단 정보가 없는 작업입니다 (새로 만든 작업부터 지원돼요)")
    pid = parent.get("profile_id")
    paths = profile_paths(pid) if pid else None
    if not paths:
        raise ValueError("프로필로 만든 작업만 문단 재생성이 가능합니다")
    src = job_output(parent_id)
    if not src:
        raise ValueError("원본 오디오 파일이 없습니다")

    _ensure_dirs()
    settings = parent.get("settings") or {}
    job_id = uuid.uuid4().hex[:10]
    job = _new_job(job_id, parent["text"], parent.get("profile"), pid,
                   settings, title=parent.get("title"),
                   parent={"job": parent_id, "kind": "paragraph",
                           "index": index},
                   version=int(parent.get("version", 1)) + 1)
    job.update({"status": "generating", "stage": "takes"})
    with _LOCK:
        JOBS[job_id] = job
    on_progress = _make_progress(job)

    def run():
        jdir = os.path.join(HISTORY_DIR, job_id)
        os.makedirs(jdir, exist_ok=True)
        out = os.path.join(jdir, "output.wav")
        t_start = time.time()
        try:
            regenerate_paragraph(src, paras, index, paths[0], paths[1],
                                 paths[2], out, fast=settings.get("fast", False),
                                 takes=settings.get("takes", DEFAULT_TAKES),
                                 on_progress=on_progress)
            _finish_job(job, out, t_start)
        except Exception as e:
            job.update({"status": "error", "error": str(e)[-300:]})
        finally:
            _persist_job(job, jdir)

    threading.Thread(target=run, daemon=True).start()
    return job_id


def rename_history(job_id, title):
    """작업 이름 변경 — 라이브러리에서 알아보기 쉽게."""
    title = (title or "").strip()[:60]
    if not title:
        raise ValueError("이름이 비어 있습니다")
    meta_p = os.path.join(HISTORY_DIR, job_id, "meta.json")
    with _LOCK:
        if job_id in JOBS:
            JOBS[job_id]["title"] = title
    if os.path.exists(meta_p):
        with open(meta_p, encoding="utf-8") as f:
            meta = json.load(f)
        meta["title"] = title
        with open(meta_p, "w", encoding="utf-8") as f:
            json.dump(meta, f, ensure_ascii=False, indent=2)
    return title


def delete_history(job_id):
    with _LOCK:
        JOBS.pop(job_id, None)
    shutil.rmtree(os.path.join(HISTORY_DIR, job_id), ignore_errors=True)


def get_job(job_id):
    with _LOCK:
        job = JOBS.get(job_id)
        if job:
            return dict(job)
    meta = os.path.join(HISTORY_DIR, job_id, "meta.json")  # 서버 재시작 후
    if os.path.exists(meta):
        with open(meta, encoding="utf-8") as f:
            return json.load(f)
    return None


def job_output(job_id):
    p = os.path.join(HISTORY_DIR, job_id, "output.wav")
    return p if os.path.exists(p) else None


def list_history(limit=20):
    _ensure_dirs()
    items = []
    for jid in os.listdir(HISTORY_DIR):
        meta = os.path.join(HISTORY_DIR, jid, "meta.json")
        if os.path.exists(meta):
            try:
                with open(meta, encoding="utf-8") as f:
                    items.append(json.load(f))
            except (OSError, json.JSONDecodeError):
                continue
    items.sort(key=lambda x: x.get("created", ""), reverse=True)
    return items[:limit]
