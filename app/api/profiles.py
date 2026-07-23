"""보이스 프로필 + 생성 작업(세션) 관리 — 앱 계층.

- 프로필: 가이드 문장 녹음들 → 병합·분석해 참조 자산(창/받아쓰기/자연 통계)을
  캐시. 한 번 만들면 이후 생성마다 참조 준비(노이즈 제거+받아쓰기+분석)를
  건너뛴다.
- 작업(job): 생성을 백그라운드 스레드로 돌리고 진행 상황(테이크 오디션 점수)을
  실시간 노출. 완료물은 히스토리로 영구 저장 — 세션 분리·보관.

영속 접근은 전부 api.storage.store(어댑터)를 경유한다 — 업데이트 내구성과
클라우드 전환을 위해. 저장 위치·백엔드는 web/storage.py 참고.
"""
import os
import shutil
import threading
import time
import uuid

from api import storage
from voxa.lang import set_speech_language

# 가이드 문장: 지표로 검증된 결함 차원(끝음 유형·억양 역동성·호흡·속도·강세)을
# 고루 커버하도록 설계. 전체 낭독 약 90초.
# 가이드 대본은 언어마다 한 벌씩. 문장 열 개가 각각 다른 운율을 담당하므로
# (인사 톤 · 호흡 · 의문문 끝음 · 감탄 · 숫자 · 긴 문장 · 빠름 · 느림 · 대화체 ·
# 마무리) 번역이 아니라 같은 역할을 하는 문장으로 짝을 맞춘다. 프로필의 언어와
# 낭독할 언어가 어긋나면 Whisper 전사가 무너져 클론 품질이 같이 떨어진다.
GUIDE_KO = [
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

GUIDE_EN = [
    {"text": "Hi there, this is the first sentence in my own voice.",
     "tip": "Say it the way you would greet someone", "focus": "Greeting tone"},
    {"text": "The sky is clear today, and there is just enough wind to make it "
             "a good day for a walk.",
     "tip": "Take a small breath at the comma", "focus": "Statement and breath"},
    {"text": "But have you ever wondered how any of this actually works?",
     "tip": "Let your voice rise at the end", "focus": "Question ending"},
    {"text": "Wow, that result is genuinely surprising! It came out better than "
             "I expected.",
     "tip": "Sound like you mean it", "focus": "Emphasis"},
    {"text": "As of July 2026, the model finishes training in about 5 minutes.",
     "tip": "Say the numbers clearly", "focus": "Numbers"},
    {"text": "It cleans up the noise, learns your voice, and reads your script "
             "out loud, all of it automatically.",
     "tip": "Keep a steady rhythm, pausing at each comma", "focus": "Long sentence"},
    {"text": "Alright, this next part is the one that really matters, so stay "
             "with me.",
     "tip": "A little faster, with energy", "focus": "Quick pace"},
    {"text": "Slowly, one piece at a time, I will walk you through it.",
     "tip": "Deliberately slow and calm", "focus": "Slow pace"},
    {"text": "A friend listened and asked me, is that really your own voice?",
     "tip": "Shift your tone slightly for the quoted part", "focus": "Quoted speech"},
    {"text": "Thank you for listening this far. I will see you in the next one.",
     "tip": "Let the ending settle down gently", "focus": "Closing"},
]

GUIDE_SCRIPTS = {"ko": GUIDE_KO, "en": GUIDE_EN}

# 한국어가 기본 (기존 호출부 호환).
GUIDE_SENTENCES = GUIDE_KO


def guide_sentences(lang="ko"):
    """해당 언어의 가이드 대본. 모르는 언어면 기본값."""
    return GUIDE_SCRIPTS.get(lang) or GUIDE_KO

_LOCK = threading.Lock()
JOBS = {}  # job_id → dict (메모리; 완료물은 히스토리에 영구 저장)


def _ensure_dirs():
    pass  # store가 쓰기·목록 시 디렉토리를 자동 생성 (호환용 no-op)


def _profile_dir(pid):
    return storage.store.entity_dir("profiles", pid)


def _history_dir(job_id):
    return storage.store.entity_dir("history", job_id)


def _load_meta(pid):
    m = storage.store.read_doc("profiles", pid)
    if m is None:
        raise FileNotFoundError(pid)
    return m


def _save_meta(pid, meta):
    storage.store.write_doc("profiles", pid, meta)


def profile_lang(pid):
    """이 프로필이 말하는 언어. 언어가 없는 옛 프로필은 한국어로 본다."""
    try:
        return (_load_meta(pid) or {}).get("lang") or "ko"
    except (FileNotFoundError, OSError):
        return "ko"


def create_profile(name, lang="ko"):
    _ensure_dirs()
    pid = uuid.uuid4().hex[:10]
    os.makedirs(os.path.join(_profile_dir(pid), "raw"), exist_ok=True)
    # 이 목소리가 말하는 언어. 빌드·낭독·채점의 Whisper 전사가 이걸 따른다.
    # 언어가 없는 옛 프로필은 읽을 때 기본값(한국어)으로 본다.
    meta = {"id": pid, "name": name.strip() or "내 목소리",
            "lang": lang if lang in GUIDE_SCRIPTS else "ko",
            "created": time.strftime("%Y-%m-%d %H:%M"),
            "recordings": 0, "ready": False, "stats": None}
    _save_meta(pid, meta)
    return meta


def add_recording(pid, file_storage, idx):
    raw = os.path.join(_profile_dir(pid), "raw")
    ext = os.path.splitext(file_storage.filename or "r.webm")[1] or ".webm"
    file_storage.save(os.path.join(raw, f"{int(idx):02d}{ext}"))
    meta = _load_meta(pid)
    meta["recordings"] = len(os.listdir(raw))
    _save_meta(pid, meta)
    return meta


def add_source(pid, file_storage, denoise=True):
    """추가 소스(기존 음성/영상 파일) 등록 — 소스별 노이즈 제거 플래그 저장."""
    sdir = os.path.join(_profile_dir(pid), "sources")
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


def _archive_stats(meta):
    """재분석 전 이전 통계를 이력으로 보존 (강화 전/후 비교용). 순수 함수."""
    if meta.get("stats"):
        meta.setdefault("stats_history", []).append({
            "date": meta.get("built") or meta.get("created"),
            "stats": meta["stats"],
            **(meta.get("built_with") or {})})
    return meta


def _snapshot_version(pdir, meta, vnum):
    """현재 참조 자산을 versions/vN/ 스냅샷으로 보존하고 meta가 그걸 가리키게.

    빌드 산출물은 pdir 루트에 생성되는데, 다음 빌드가 같은 이름으로 덮어쓴다.
    스냅샷 사본을 활성 자산으로 쓰면 이후 빌드가 실패하거나 결과가 나빠도
    이전 버전이 온전히 남는다 (롤백의 재료).
    """
    vdir = os.path.join(pdir, "versions", f"v{vnum}")
    os.makedirs(vdir, exist_ok=True)
    for key in ("ref_wav", "natural_wav"):
        base = os.path.basename(meta[key])
        src = os.path.join(pdir, meta[key])
        dst = os.path.join(vdir, base)
        if os.path.abspath(src) != os.path.abspath(dst):
            shutil.copy(src, dst)
        meta[key] = os.path.join("versions", f"v{vnum}", base)
    entry = {"version": vnum, "built": meta.get("built") or meta.get("created"),
             "stats": meta.get("stats"), "ref_text": meta.get("ref_text"),
             "denoised": meta.get("denoised", True),
             "built_with": meta.get("built_with"),
             "ref_wav": meta["ref_wav"], "natural_wav": meta["natural_wav"]}
    storage.store.write_json(os.path.join(vdir, "version.json"), entry)
    meta["version"] = vnum
    log = meta.setdefault("version_log", [])
    if not any(e.get("version") == vnum for e in log):
        log.append({"version": vnum, "built": entry["built"],
                    "stats": entry["stats"],
                    "built_with": entry["built_with"]})
    return meta


def rollback_profile(pid, version):
    """활성 버전을 과거 스냅샷으로 되돌린다 (강화가 마음에 안 들 때).

    스냅샷 파일은 그대로 두고 meta 포인터만 바꾸므로 즉시·무손실이며,
    다시 최신 버전으로 '롤포워드'도 같은 방법으로 가능하다.
    """
    pdir = _profile_dir(pid)
    vfile = os.path.join(pdir, "versions", f"v{int(version)}", "version.json")
    v = storage.store.read_json(vfile)
    if v is None:
        raise ValueError(f"버전 v{version}이(가) 없습니다")
    meta = _load_meta(pid)
    meta.update({"ref_wav": v["ref_wav"], "natural_wav": v["natural_wav"],
                 "ref_text": v["ref_text"], "stats": v["stats"],
                 "denoised": v.get("denoised", True),
                 "version": v["version"], "ready": True})
    _save_meta(pid, meta)
    return meta


def build_profile(pid, denoise=True, on_progress=None):
    """소스 전처리(개별 노이즈 제거) → 병합 → 참조 자산 캐시 → 통계 분석.

    입력 = 가이드 녹음(일괄 denoise 플래그) + 추가 소스(소스별 플래그).
    각자 플래그대로 전처리한 뒤 병합하므로, 이후 단계는 재차 제거하지 않는다.
    재실행 가능(프로필 강화): 소스를 더 넣고 다시 부르면 전체를 재분석하고,
    이전 통계는 stats_history에 남아 전/후 비교에 쓰인다.
    on_progress: 단계 콜백 {"stage": prep|reference|stats, ...}
    """
    def _notify(**ev):
        if on_progress:
            try:
                on_progress(ev)
            except Exception:
                pass
    from voxa.media.audio import concat_to_wav
    from voxa.clone import prepare_reference
    from voxa.denoise import preprocess_source
    from voxa.analysis.prosody import (final_f0_slopes, prosody_features,
                              stress_features)

    pdir = _profile_dir(pid)
    meta = _archive_stats(_load_meta(pid))
    # 버전 개념 이전의 프로필: 빌드가 루트 자산을 덮어쓰기 전에 현재 상태를
    # v1 스냅샷으로 소급 보존 (빌드 실패·저품질 강화로부터 보호)
    if meta.get("ready") and meta.get("ref_wav") \
            and not str(meta["ref_wav"]).startswith("versions"):
        meta.setdefault("builds", 1)
        _snapshot_version(pdir, meta, int(meta["builds"]))
        _save_meta(pid, meta)
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
    total = len(guided) + len(sources)
    for i, f in enumerate(guided):  # 가이드 녹음: 일괄 플래그
        _notify(stage="prep", i=i + 1, n=total)
        prepped.append(preprocess_source(
            f, os.path.join(prep_dir, f"g{i:02d}.wav"), denoise=denoise))
    for i, s in enumerate(sources):  # 추가 소스: 소스별 플래그
        _notify(stage="prep", i=len(guided) + i + 1, n=total)
        prepped.append(preprocess_source(
            os.path.join(pdir, "sources", s["file"]),
            os.path.join(prep_dir, f"s{i:02d}.wav"),
            denoise=s.get("denoise", True)))

    merged = os.path.join(pdir, "merged.wav")
    concat_to_wav(prepped, merged)
    _notify(stage="reference")
    ref_wav, ref_text, natural = prepare_reference(merged, pdir,
                                                   denoise=False)

    _notify(stage="stats")
    feats = prosody_features(natural)
    stress = stress_features(natural) or {}
    slopes = final_f0_slopes(natural)
    meta.update({
        "ready": True,
        "built": time.strftime("%Y-%m-%d %H:%M"),
        "builds": int(meta.get("builds", 0)) + 1,
        "built_with": {"recordings": len(guided), "sources": len(sources)},
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
    _snapshot_version(pdir, meta, int(meta["builds"]))
    _save_meta(pid, meta)
    return meta


def list_profiles():
    out = []
    for pid in storage.store.list_ids("profiles"):
        m = storage.store.read_doc("profiles", pid)
        if m is not None:
            out.append(m)
    return out


def delete_profile(pid):
    storage.store.delete_entity("profiles", pid)


def profile_paths(pid):
    """캐시된 참조 자산 → (ref_wav, ref_text, natural_wav). 미완성이면 None."""
    meta = _load_meta(pid)
    if not meta.get("ready"):
        return None
    pdir = _profile_dir(pid)
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
    """코어 진행 이벤트 → 작업 레코드 반영 + 즉시 저장.

    진행 중에도 디스크에 남겨야 새로고침·재접속 후에도 작업 센터가
    "⏳ 진행 중"으로 추적할 수 있다 (완료 시점에만 쓰면 그때까지 안 보임).
    """
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
            _persist_job(job)
    return on_progress


def _finish_job(job, out, t_start):
    picked = max(job["takes"], key=lambda t: t.get("sel", -1e9), default=None)
    elapsed = time.time() - t_start
    rtf = None
    audio = None
    try:  # 처리량 북극성: RTF = 처리 시간 / 오디오 길이
        import soundfile as sf
        audio = max(sf.info(out).duration, 0.1)
        rtf = round(elapsed / audio, 1)
    except Exception:
        pass
    try:  # 가라오케 가사 뷰용 단어 타임라인 (실패해도 작업은 성공)
        from voxa.analysis.prosody import prosody_deps_available, word_timeline
        if prosody_deps_available():
            job["words"] = word_timeline(out)
    except Exception:
        pass
    fast = bool(job.get("settings", {}).get("fast"))
    cold = job.pop("_cold", False)
    if not job.get("parent"):  # 부분 재생성은 처리량 통계에서 제외
        from api.rates import update_rate, mark_warm, get_rates
        if cold and audio:
            # 콜드 실행은 모델 로드가 소요시간을 부풀린다. 그 초과분을 cold_start로
            # 따로 학습하고, warm RTF는 오염시키지 않는다.
            warm_rtf = get_rates()["clone_fast_rtf" if fast else "clone_rtf"]
            update_rate("cold_start", elapsed - audio * warm_rtf)
        elif rtf:
            update_rate("clone_fast_rtf" if fast else "clone_rtf", rtf)
        mark_warm(fast)  # 모델이 이제 상주 — 다음 클론부터 warm
    job.update({"status": "done", "stage": "done",
                "pns": job.pop("final_pns", None)
                or (picked.get("pns") if picked else None),
                "elapsed_sec": round(elapsed), "rtf": rtf})


def _persist_job(job, jdir=None):
    storage.store.write_doc("history", job["id"], job)


def start_clone_job(text, fast, ref_path=None, profile_id=None,
                    profile_name=None, takes=None, title=None):
    """백그라운드 생성 작업 시작 → job_id. 진행은 JOBS[job_id]에 기록."""
    from voxa.clone import DEFAULT_TAKES, clone_voice, synthesize_best

    _ensure_dirs()
    job_id = uuid.uuid4().hex[:10]
    n_takes = takes or (1 if fast else DEFAULT_TAKES)
    job = _new_job(job_id, text, profile_name, profile_id,
                   {"fast": bool(fast), "takes": n_takes}, title=title)
    from api.rates import estimate_clone_eta, is_warm
    rate = None
    if profile_id:
        try:
            rate = (_load_meta(profile_id).get("stats") or {}).get("rate")
        except (OSError, AttributeError):
            pass
    # First clone of this model in the process pays the model-load cost; the ETA
    # and the rate learning below account for it separately.
    warm = is_warm(fast)
    job["_cold"] = not warm
    job["eta_sec"] = estimate_clone_eta(text, fast=fast, speech_rate=rate, warm=warm)
    with _LOCK:
        JOBS[job_id] = job
        _persist_job(job)  # 시작 즉시 저장 — 새로고침해도 작업 센터에 보이게
    on_progress = _make_progress(job)

    def run():
        jdir = _history_dir(job_id)
        os.makedirs(jdir, exist_ok=True)
        out = os.path.join(jdir, "output.wav")
        t_start = time.time()
        try:
            # 이 작업의 음성 언어를 스레드 컨텍스트에 심는다 (Whisper 전사 기준).
            # try 안에 둬야 여기서 실패해도 잡이 조용히 멈추지 않고 오류로 남는다.
            set_speech_language(profile_lang(profile_id) if profile_id else "ko")
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
    from voxa.clone import DEFAULT_TAKES, regenerate_paragraph

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
    from api.rates import estimate_clone_eta
    job["eta_sec"] = estimate_clone_eta(paras[index]["text"],
                                        fast=settings.get("fast", False))
    with _LOCK:
        JOBS[job_id] = job
        _persist_job(job)
    on_progress = _make_progress(job)

    def run():
        jdir = _history_dir(job_id)
        os.makedirs(jdir, exist_ok=True)
        out = os.path.join(jdir, "output.wav")
        t_start = time.time()
        try:
            # 음성 언어를 스레드 컨텍스트에 심는다 (Whisper 전사 기준).
            # try 안에 둬야 실패해도 잡이 조용히 멈추지 않고 오류로 남는다.
            set_speech_language(profile_lang(pid) if pid else "ko")
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


def start_build_job(pid, denoise=True):
    """프로필 분석(빌드/강화)을 백그라운드 작업으로 → job_id.

    분석은 1~2분 걸리므로 동기 요청은 UX 사각지대였다 (브라우저를 닫으면
    진행을 다시 못 봄). 작업 센터에서 추적 + ETA는 학습 음성 총 길이 실측.
    """
    from voxa.media.audio import media_duration
    from api.rates import estimate_build_eta

    meta = _load_meta(pid)  # 없으면 FileNotFoundError → 호출부 404
    _ensure_dirs()
    pdir = _profile_dir(pid)
    total = 0.0
    raw = os.path.join(pdir, "raw")
    files = ([os.path.join(raw, f) for f in os.listdir(raw)
              if not f.startswith(".")] if os.path.isdir(raw) else [])
    files += [os.path.join(pdir, "sources", s["file"])
              for s in meta.get("sources", [])]
    for f in files:
        d = media_duration(f)
        total += min(d or 30, 180)  # 소스는 앞 3분만 쓰므로 상한

    job_id = uuid.uuid4().hex[:10]
    job = {"id": job_id, "kind": "profile_build", "status": "running",
           "stage": "prep", "title": f"프로필 분석: {meta.get('name', '')}",
           "profile_id": pid, "error": None,
           "created": time.strftime("%Y-%m-%d %H:%M"),
           "started_ts": time.time(),
           "eta_sec": estimate_build_eta(total)}
    with _LOCK:
        JOBS[job_id] = job
        _persist_job(job)

    def on_progress(ev):
        with _LOCK:
            s = ev.get("stage")
            job["stage"] = (f"prep {ev['i']}/{ev['n']}" if s == "prep" else s)
            _persist_job(job)

    def run():
        # 이 작업의 음성 언어를 스레드 컨텍스트에 심는다 (Whisper 전사 기준).
        set_speech_language(profile_lang(pid))
        t0 = time.time()
        try:
            build_profile(pid, denoise=denoise, on_progress=on_progress)
            elapsed = time.time() - t0
            if total > 5:
                from api.rates import update_rate
                update_rate("build_factor", (elapsed - 20) / total)
            job.update({"status": "done", "stage": "done",
                        "elapsed_sec": round(elapsed)})
        except Exception as e:
            job.update({"status": "error", "error": str(e)[-300:]})
        finally:
            _persist_job(job)

    threading.Thread(target=run, daemon=True).start()
    return job_id


def start_performance_job(parent_id, index, rec_path, denoise=True):
    """선택한 문단을 사용자 연기 녹음의 운율로 다시 생성한 새 버전 작업.

    참조를 연기 녹음으로 교체하므로 감정·리듬·강조가 결과에 전이되고,
    테이크 채점 기준도 자동으로 '연기를 얼마나 잘 따라했나'가 된다.
    """
    from voxa.clone import (DEFAULT_TAKES, prepare_performance,
                            regenerate_paragraph)

    parent = get_job(parent_id)
    if not parent or parent.get("status") != "done":
        raise ValueError("완성된 작업이 아닙니다")
    paras = parent.get("paragraphs")
    if not paras or not (0 <= index < len(paras)):
        raise ValueError("문단 정보가 없는 작업입니다 (새로 만든 작업부터 지원돼요)")
    src = job_output(parent_id)
    if not src:
        raise ValueError("원본 오디오 파일이 없습니다")

    _ensure_dirs()
    settings = parent.get("settings") or {}
    pid = parent.get("profile_id")
    job_id = uuid.uuid4().hex[:10]
    job = _new_job(job_id, parent["text"], parent.get("profile"),
                   pid, settings,
                   title=parent.get("title"),
                   parent={"job": parent_id, "kind": "performance",
                           "index": index},
                   version=int(parent.get("version", 1)) + 1)
    job.update({"status": "generating", "stage": "performance"})
    from api.rates import estimate_clone_eta
    job["eta_sec"] = estimate_clone_eta(paras[index]["text"],
                                        fast=settings.get("fast", False)) + 25
    with _LOCK:
        JOBS[job_id] = job
        _persist_job(job)
    on_progress = _make_progress(job)

    def run():
        jdir = _history_dir(job_id)
        os.makedirs(jdir, exist_ok=True)
        out = os.path.join(jdir, "output.wav")
        t_start = time.time()
        try:
            # 음성 언어를 스레드 컨텍스트에 심는다 (Whisper 전사 기준).
            # try 안에 둬야 실패해도 잡이 조용히 멈추지 않고 오류로 남는다.
            set_speech_language(profile_lang(pid) if pid else "ko")
            perf, perf_text = prepare_performance(rec_path, jdir,
                                                  denoise=denoise)
            job["perf_text"] = perf_text  # "이렇게 들렸어요" (투명성)
            job["status"] = "generating"
            job["stage"] = "takes"
            regenerate_paragraph(src, paras, index, perf, perf_text, perf,
                                 out, fast=settings.get("fast", False),
                                 takes=settings.get("takes", DEFAULT_TAKES),
                                 on_progress=on_progress)
            _finish_job(job, out, t_start)
        except Exception as e:
            job.update({"status": "error", "error": str(e)[-300:]})
        finally:
            if rec_path and os.path.exists(rec_path):
                os.remove(rec_path)
            _persist_job(job, jdir)

    threading.Thread(target=run, daemon=True).start()
    return job_id


def rename_history(job_id, title):
    """작업 이름 변경 — 라이브러리에서 알아보기 쉽게."""
    title = (title or "").strip()[:60]
    if not title:
        raise ValueError("이름이 비어 있습니다")
    with _LOCK:
        if job_id in JOBS:
            JOBS[job_id]["title"] = title
    meta = storage.store.read_doc("history", job_id)
    if meta is not None:
        meta["title"] = title
        storage.store.write_doc("history", job_id, meta)
    return title


def delete_history(job_id):
    with _LOCK:
        JOBS.pop(job_id, None)
    storage.store.delete_entity("history", job_id)


def get_job(job_id):
    with _LOCK:
        job = JOBS.get(job_id)
        if job:
            return dict(job)
    return storage.store.read_doc("history", job_id)  # 서버 재시작 후


def job_output(job_id):
    p = os.path.join(storage.store.entity_dir("history", job_id, ensure=False),
                     "output.wav")
    return p if os.path.exists(p) else None


def list_history(limit=20):
    items = []
    for jid in storage.store.list_ids("history"):
        meta = storage.store.read_doc("history", jid)
        if meta is not None:
            items.append(meta)
    items.sort(key=lambda x: x.get("created", ""), reverse=True)
    return items[:limit]


# 비종료(진행 중) 상태들. 이 상태로 저장된 작업은 그걸 돌리던 프로세스가 살아있을
# 때만 의미가 있다.
_ACTIVE_STATUSES = ("running", "generating", "preparing", "queued")


def reconcile_interrupted():
    """서버가 새로 뜨면 이전 프로세스가 돌리던 작업은 이미 끝났거나 죽은 것이다.
    그런데 그 작업이 도중에 죽으면 상태가 'preparing'/'generating'인 채로 남아,
    /api/tasks가 그걸 영원히 '진행 중'으로 보고한다(맥 앱 상단의 유령 'Rendering
    %'). 시작 시 한 번, 비종료 상태로 남은 작업을 '중단됨' 오류로 정리한다.

    새로 뜬 프로세스에는 아직 어떤 작업도 진행 중일 수 없으므로, 실제로 도는
    작업을 잘못 건드릴 위험이 없다. 정리한 개수를 돌려준다."""
    n = 0
    for jid in storage.store.list_ids("history"):
        meta = storage.store.read_doc("history", jid)
        if meta and meta.get("status") in _ACTIVE_STATUSES:
            meta["status"] = "error"
            meta["error"] = meta.get("error") or "interrupted"
            storage.store.write_doc("history", jid, meta)
            n += 1
    return n


# 10분 무진행이면 멈춘 것으로 본다. 진행 이벤트마다 문서가 다시 써지므로, 콜드
# 모델 로드(~1분)나 느린 테이크 한 번보다 충분히 길어 오탐하지 않는다.
STALE_SILENCE_SEC = 600


def reconcile_stale(silence=STALE_SILENCE_SEC):
    """세션 중 워치독: reconcile_interrupted가 재시작만 커버하는 것과 달리, 엔진이
    오래 돌면서 워커가 죽어 작업이 비종료 상태로 멈추는 경우를 잡는다.

    진행 이벤트마다 작업 문서가 다시 써지므로 문서 mtime이 하트비트다. 비종료
    작업의 문서가 silence초 넘게 갱신되지 않았으면 멈춘 것으로 보고 오류 처리한다.
    실제로 도는(진행 중인) 작업은 최근에 써졌으므로 건드리지 않는다."""
    now = time.time()
    n = 0
    for jid in storage.store.list_ids("history"):
        meta = storage.store.read_doc("history", jid)
        if not meta or meta.get("status") not in _ACTIVE_STATUSES:
            continue
        mt = storage.store.doc_mtime("history", jid)
        if mt is not None and now - mt > silence:
            meta["status"] = "error"
            meta["error"] = meta.get("error") or "stuck (no progress)"
            storage.store.write_doc("history", jid, meta)
            n += 1
    return n
