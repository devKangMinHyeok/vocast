"""보이스 클로닝 파이프라인 (Qwen3-TTS, Apple Silicon 전용).

"지표 먼저 → 후보 경쟁 → 최고 선택"으로 확정한 설정:
- 참조 음성은 RNNoise로 전처리 (모든 조합에서 SIM +0.02)
- 기본 모델 1.7B-Base-8bit (SIM 0.917~0.945, CER 0%, MOS 3.50)
- 빠른 모델 0.6B-Base-8bit (SIM 0.921, CER 0%, MOS 3.39)
"""
import importlib.util
import os
import subprocess
import sys
import tempfile

from . import ROOT
from .audio import run_ffmpeg

MODEL_BEST = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit"
MODEL_FAST = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
WHISPER = "mlx-community/whisper-large-v3-turbo"
MAX_REF_SEC = 15  # 참조는 앞 15초면 충분


def clone_available():
    """이 환경에서 보이스 클로닝을 쓸 수 있는지 (mlx 설치 여부)."""
    return (importlib.util.find_spec("mlx_audio") is not None
            and importlib.util.find_spec("mlx_whisper") is not None)


def prepare_reference(ref_path, workdir, max_sec=MAX_REF_SEC, denoise=True):
    """참조 파일(영상 가능) → (참조 wav, 받아쓰기, 자연 발화 전체 wav).

    ① 전체(최대 2분)를 노이즈 제거(기본, 끌 수 있음) — 화자의 "자연 운율
       기준"이 된다. 검증: 노이즈 제거 참조가 모든 조합에서 SIM 우세.
    ② 그중 억양이 살아있고 무음 경계에 스냅된 창을 클로닝 참조로 자동 선택
       (운율 의존성 없으면 앞 max_sec 초로 폴백 — 기존 동작).
    """
    full_clean = os.path.join(workdir, "ref_full_clean.wav")
    if denoise:
        # 엔진 디스패처 경유 — DFN 설치 시 하이브리드(말끝 보존·발화 중 제거)
        from .denoise import denoise_to_wav
        denoise_to_wav(ref_path, full_clean, max_sec=120)
    else:
        run_ffmpeg(["-i", ref_path, "-t", "120",
                    "-af", "aformat=channel_layouts=mono",
                    "-c:a", "pcm_s16le", full_clean])

    clean = os.path.join(workdir, "ref_clean.wav")
    try:
        from .prosody import prosody_deps_available, select_reference_window
        if not prosody_deps_available():
            raise ImportError
        a, b = select_reference_window(full_clean)
        run_ffmpeg(["-ss", f"{a:.2f}", "-t", f"{b - a:.2f}", "-i", full_clean,
                    "-c:a", "pcm_s16le", clean])
    except ImportError:
        run_ffmpeg(["-t", str(max_sec), "-i", full_clean,
                    "-c:a", "pcm_s16le", clean])

    import mlx_whisper
    text = mlx_whisper.transcribe(
        clean, path_or_hf_repo=WHISPER, language="ko")["text"].strip()
    if not text:
        raise RuntimeError("참조 파일에서 말소리를 찾지 못했습니다. "
                           "발화가 또렷한 구간이 필요해요.")

    # 참조 억양 증폭 (적응적): 차분한 화자만 필요한 만큼 높낮이를 키운다.
    # 이미 활기찬 화자는 α≈1 → 생략. 받아쓰기는 증폭 전 오디오로 이미 확보.
    try:
        from .prosody import (exaggerate_pitch, prosody_features,
                              reference_exaggeration_alpha)
        alpha = reference_exaggeration_alpha(prosody_features(full_clean))
        if alpha >= 1.05:
            clean = exaggerate_pitch(
                clean, os.path.join(workdir, "ref_lively.wav"), alpha)
    except ImportError:
        pass
    return clean, text, full_clean


_worker = {"proc": None}
_worker_lock = None


def _worker_generate(model, text, ref_wav, ref_text, out_dir, prefix,
                     timeout_sec):
    """상주 워커로 생성 (모델 1회 로드 — 테이크당 ~10초 절약, RTF 최적화).

    실패/타임아웃 시 워커를 버리고 예외 → 호출부가 CLI 폴백.
    """
    import json
    import threading
    global _worker_lock
    if _worker_lock is None:
        _worker_lock = threading.Lock()
    with _worker_lock:
        p = _worker["proc"]
        if p is None or p.poll() is not None:
            p = subprocess.Popen(
                [sys.executable, os.path.join(ROOT, "core", "tts_worker.py")],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL, text=True)
            _worker["proc"] = p
        req = {"model": model, "text": text, "ref_audio": ref_wav,
               "ref_text": ref_text, "out_dir": out_dir, "prefix": prefix}
        p.stdin.write(json.dumps(req) + "\n")
        p.stdin.flush()
        resp = {}

        def read():
            line = p.stdout.readline()
            resp["line"] = line

        t = threading.Thread(target=read, daemon=True)
        t.start()
        t.join(timeout_sec)
        if t.is_alive() or not resp.get("line"):
            p.kill()
            _worker["proc"] = None
            raise RuntimeError("워커 응답 없음 (타임아웃)")
        r = json.loads(resp["line"])
        if not r.get("ok"):
            raise RuntimeError(r.get("error", "워커 생성 실패"))


def synthesize(text, ref_wav, ref_text, output_path, fast=False, retries=1,
               timeout_sec=600):
    """참조 목소리로 대본을 읽은 wav 생성.

    1순위: 상주 워커 (모델 로드 1회). 실패 시 CLI 서브프로세스 폴백 —
    저사양(GPU 없는) CI 러너에서 mlx_audio가 파일을 안 만들고 종료코드 0을
    내거나 멈추는 경우가 관찰됨 → 출력 파일 검증 + 타임아웃 + 재시도.
    """
    model = MODEL_FAST if fast else MODEL_BEST
    out_dir = os.path.dirname(os.path.abspath(output_path)) or "."
    prefix = os.path.splitext(os.path.basename(output_path))[0]
    try:
        _worker_generate(model, text, ref_wav, ref_text, out_dir, prefix,
                         timeout_sec)
        if os.path.exists(output_path):
            return output_path
    except (RuntimeError, OSError, ValueError):
        pass  # CLI 폴백

    cmd = [sys.executable, "-m", "mlx_audio.tts.generate",
           "--model", model, "--text", text,
           "--ref_audio", ref_wav, "--ref_text", ref_text,
           "--join_audio", "--audio_format", "wav",
           "--output_path", out_dir, "--file_prefix", prefix]
    detail = ""
    for _ in range(1 + retries):
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True,
                                  timeout=timeout_sec)
        except subprocess.TimeoutExpired:
            detail = f"{timeout_sec}초 타임아웃 (생성이 멈춘 것으로 판단)"
            continue
        if proc.returncode == 0 and os.path.exists(output_path):
            return output_path
        detail = (proc.stderr or proc.stdout or "")[-400:]
    raise RuntimeError(f"TTS 생성 실패 (재시도 포함 {1 + retries}회): {detail}")


# 게이트(82)는 릴리스 최저 보증선이고, 선별 조기종료 목표는 그보다 높게 잡는다 —
# 목표를 게이트와 같게 두면 출력이 항상 "합격선 언저리"에 머문다 (청취 피드백으로 실측:
# 조기종료 82 시절 웹 출력 PNS 82.5 vs 베스트 테이크 87.0).
PNS_TARGET = 87.0  # 이 점수를 넘는 테이크가 나오면 조기 채택
DEFAULT_TAKES = 6  # 일반 모드 테이크 수 (품질 우선 — 사용자 확인: 시간보다 품질)
BREATH_TARGET = (0.5, 0.7)   # 문장 경계 호흡 목표 범위(초) — 읽기 발화 실측 분포
CLAUSE_TARGET = (0.18, 0.28)  # 쉼표(절) 경계 호흡 — 문장보다 짧게 (경계 강도 위계)
CLAUSE_MIN = 0.10             # 쉼표 호흡 최소치 (실측: 모델이 0.09초로 무시하기도)


def ensure_breath_pauses(wav_path, script):
    """경계 호흡 보장 후처리 (구조적 보정) — 문장 경계 + 쉼표(절) 경계.

    통짜 생성은 억양이 자연스럽지만, 경계 호흡은 테이크 운에 달려 있다
    (실측: 문장 경계 0.0~0.6초, 쉼표는 0.09초로 무시하는 경우도). 부족한
    경계에 자연 길이 무음을 채워 넣는다 — 문장 0.5~0.7초, 쉼표 0.18~0.28초
    (문헌: 경계 강도가 높을수록 휴지가 길다). 억양은 건드리지 않는다.
    """
    from .prosody import (BREATH_MIN, sentence_boundary_info,
                          split_breath_units)
    units = split_breath_units(script)
    if len(units) < 2:
        return wav_path
    infos = sentence_boundary_info(wav_path, script, units=units)
    short = [b for b in infos
             if b["gap"] < (BREATH_MIN if b.get("kind") == "sentence"
                            else CLAUSE_MIN)]
    if not short:
        return wav_path

    import numpy as np
    import soundfile as sf
    y, sr = sf.read(wav_path, dtype="float32")
    rng = np.random.default_rng(len(script))  # 대본 고정 시드 → 재현 가능
    fade = int(sr * 0.01)
    pieces, cursor = [], 0
    for b in sorted(short, key=lambda x: x["insert_at"]):
        lo, hi = (BREATH_TARGET if b.get("kind") == "sentence"
                  else CLAUSE_TARGET)
        need = float(rng.uniform(lo, hi)) - b["gap"]
        cut = int(b["insert_at"] * sr)
        head = y[cursor:cut].copy()
        if len(head) > fade and b["silence"] is None:
            head[-fade:] *= np.linspace(1, 0, fade)  # 무음이 없던 곳은 페이드로 이음
        pieces += [head, np.zeros(int(need * sr), dtype="float32")]
        cursor = cut
    pieces.append(y[cursor:])
    sf.write(wav_path, np.concatenate(pieces), sr)
    return wav_path


RATE_TOLERANCE = 0.15   # 조음속도 허용 편차 (±15%) — 벗어나면 선별 감점
RATE_PENALTY = 15.0     # 편차 1.0당 PNS 감점량
ENDING_PENALTY = 8.0    # 끝음 스타일 불일치(0~1) 최대 감점 — "끝음이 AI 같다" 대응
STRESS_PENALTY = 6.0    # 음절 강약 불일치(0~1) 최대 감점 — 균일 강세/과분절 대응
CLIFF_PENALTY = 8.0     # 끝음 절벽(확 내려꽂음) 최대 감점 — 실측 사람 -7.8 vs 클론 -17
WORD_DROP_PENALTY = 8.0  # 어미 단어 내부 낙하(줬-어-요 계단 하강) 최대 감점
SWALLOW_PENALTY = 6.0    # '먹힌 단어'(국소 강약 결함) 최대 감점 — worst-case
PNS_DOMINANCE = 8.0     # 지배 규칙: 최고 PNS보다 이만큼 낮은 테이크는
                        # 스타일 감점이 유리해도 선정 불가 (실사용 사고:
                        # 프로필 통계가 틀어지자 최저 PNS 테이크가 선정됨)


def pick_best_take(takes):
    """테이크 목록 [{'pns','sel',...}] → 선정 인덱스. 순수 함수.

    품질(PNS)이 최고 대비 PNS_DOMINANCE 이내인 후보 중에서 선별 점수 최고를
    뽑는다 — 스타일 가드는 동급 품질 사이의 심판이지, 품질을 뒤집는 권한이 없다.
    """
    if not takes:
        return -1
    max_pns = max(t["pns"] for t in takes)
    best_i, best_sel = -1, -1e18
    for i, t in enumerate(takes):
        if t["pns"] < max_pns - PNS_DOMINANCE:
            continue
        if t["sel"] > best_sel:
            best_sel, best_i = t["sel"], i
    return best_i
# 주의: 긴 대본의 청크 분할 생성은 실측으로 기각됨 — 2문장/4~5문장 청크 모두
# 통짜 생성보다 나빴다 (PNS 77~81 vs 85, 페이스 6.7~7.9 vs 9.2음절/s).
# 이 모델은 긴 글을 통째로 읽을 때 페이스·리듬이 가장 자연스럽다.


def _selection_score(pns, gen_rate, natural_rate):
    """테이크 선별 점수 = PNS − 말 속도 이탈 감점. 순수 함수.

    속도는 PNS에 없던 사각지대였다 (실측: 테이크마다 8.6~10.7음절/s로
    출렁이고, 빠른 테이크가 '붙여 읽는' 느낌의 주범인데 그대로 통과됐음).
    """
    ratio = gen_rate / max(natural_rate, 1e-6)
    return pns - RATE_PENALTY * max(0.0, abs(ratio - 1.0) - RATE_TOLERANCE)


def _notify(on_progress, **event):
    """진행 콜백 (선택). 앱 계층이 시각화에 쓴다 — 실패해도 파이프라인은 계속."""
    if on_progress:
        try:
            on_progress(event)
        except Exception:
            pass


PARAGRAPH_SENTS = 6      # 문단 단위(파이프라인 재사용 단위)의 최대 문장 수
PARA_GAP = (0.8, 1.1)    # 문단 사이 호흡(초) — 문장(0.5~0.7)보다 김 (경계 위계)


def split_paragraphs(text, max_sents=PARAGRAPH_SENTS):
    """긴 원고를 문단 단위로 분할 (순수 함수). 빈 줄을 우선 존중하고,
    문단이 max_sents를 넘으면 다시 나눈다.

    문단(≤6문장, ≈15~40초)이 파이프라인의 재사용 단위 — 실측으로 검증된
    최적 생성 크기(짧으면 전달력 붕괴, 35초+ 통짜는 선별 약화)다.
    """
    from .prosody import split_sentences
    blocks = [b.strip() for b in text.split("\n\n") if b.strip()]
    if not blocks:
        blocks = [text.strip()]
    paras = []
    for b in blocks:
        sents = split_sentences(b.replace("\n", " "))
        for i in range(0, len(sents), max_sents):
            paras.append(" ".join(sents[i:i + max_sents]))
    return [p for p in paras if p]


def build_prosody_ctx(natural_wav):
    """화자의 자연 운율 컨텍스트 — 문단들이 공유하고, 부분 재생성도 재사용."""
    from .prosody import ending_metrics, prosody_features, stress_features
    feats = prosody_features(natural_wav)
    slopes, cliff = ending_metrics(natural_wav)
    return {"feats": feats, "rate": feats["artic_rate"], "slopes": slopes,
            "stress": stress_features(natural_wav), "cliff": cliff,
            "wav": natural_wav}


def splice_paragraphs_meta(paragraphs, index, new_dur):
    """문단 index를 new_dur(초) 길이로 교체한 뒤의 경계 목록 (순수 함수)."""
    old = paragraphs[index]
    delta = new_dur - (old["end"] - old["start"])
    out = []
    for i, p in enumerate(paragraphs):
        q = dict(p)
        if i == index:
            q["end"] = round(p["start"] + new_dur, 3)
        elif i > index:
            q["start"] = round(p["start"] + delta, 3)
            q["end"] = round(p["end"] + delta, 3)
        out.append(q)
    return out


def regenerate_paragraph(parent_wav, paragraphs, index, ref_wav, ref_text,
                         natural_wav, output_path, fast=False,
                         takes=DEFAULT_TAKES, on_progress=None):
    """완성본에서 문단 하나만 다시 생성해 갈아끼운다 (부분 재생성).

    전체를 다시 만들지 않고 마음에 안 드는 문단만 교체 — 문단이 파이프라인의
    재사용 단위라서 가능. 반환: (새 문단 경계 목록, 새 문단 PNS).
    """
    import numpy as np
    import soundfile as sf
    from .audio import normalize_speech_level

    para = paragraphs[index]
    ctx = build_prosody_ctx(natural_wav)
    y, sr = sf.read(parent_wav, dtype="float32")
    if y.ndim > 1:
        y = y.mean(axis=1)
    with tempfile.TemporaryDirectory() as wd:
        part = os.path.join(wd, "part.wav")
        pns = _generate_unit(para["text"], ref_wav, ref_text, ctx, part,
                             fast=fast, takes=takes, on_progress=on_progress)
        normalize_speech_level(part)
        if sf.info(part).samplerate != sr:  # 보통 동일(24kHz) — 방어적 변환
            conv = os.path.join(wd, "part_sr.wav")
            run_ffmpeg(["-i", part, "-ar", str(sr), conv])
            part = conv
        new = sf.read(part, dtype="float32")[0]
    if new.ndim > 1:
        new = new.mean(axis=1)
    fade = int(sr * 0.01)
    if len(new) > 2 * fade:
        new[:fade] *= np.linspace(0, 1, fade)
        new[-fade:] *= np.linspace(1, 0, fade)
    a, b = int(para["start"] * sr), int(para["end"] * sr)
    sf.write(output_path, np.concatenate([y[:a], new, y[b:]]), sr)
    metas = splice_paragraphs_meta(paragraphs, index, len(new) / sr)
    metas[index]["pns"] = round(pns, 1)  # 교체된 문단은 새 점수로
    _notify(on_progress, stage="done", pns=round(pns, 1), paragraphs=metas)
    return metas, pns


def synthesize_best(text, ref_wav, ref_text, natural_wav, output_path,
                    fast=False, takes=DEFAULT_TAKES, on_progress=None):
    """best-of-N 테이크 + 문장 조합. 긴 원고는 문단 단위로 파이프라인 재사용.

    생성은 확률적이라 테이크 편차가 크다 (실측: 같은 설정으로 50~84점).
    사람 성우가 여러 테이크를 녹음해 고르듯, 북극성 지표로 자동 선별한다.
    운율 의존성이 없으면 단일 테이크 폴백.
    """
    from .audio import normalize_speech_level
    from .prosody import prosody_deps_available
    if takes <= 1 or not prosody_deps_available():
        _notify(on_progress, stage="take", i=1, n=1)
        out = synthesize(text, ref_wav, ref_text, output_path, fast=fast)
        if prosody_deps_available():
            from .prosody import reshape_energy_contour
            ensure_breath_pauses(out, text)
            reshape_energy_contour(out, out)
            normalize_speech_level(out)
        _notify(on_progress, stage="done")
        return out, None

    ctx = build_prosody_ctx(natural_wav)

    paras = split_paragraphs(text)
    if len(paras) <= 1:
        pns = _generate_unit(text, ref_wav, ref_text, ctx, output_path,
                             fast=fast, takes=takes, on_progress=on_progress)
        normalize_speech_level(output_path)
        import soundfile as sf
        dur = sf.info(output_path).duration
        _notify(on_progress, stage="done", pns=round(pns, 1),
                paragraphs=[{"text": text, "start": 0.0,
                             "end": round(dur, 3), "pns": round(pns, 1)}])
        return output_path, pns

    # 문단 배치: 각 문단이 동일 파이프라인(테이크→선별→조합)을 재사용
    import numpy as np
    import soundfile as sf
    rng = np.random.default_rng(len(text))
    pieces, sr_out, pns_list = [], 24_000, []
    with tempfile.TemporaryDirectory() as wd:
        for pi, para in enumerate(paras):
            _notify(on_progress, stage="paragraph", i=pi + 1, n=len(paras))
            wrapped = (None if on_progress is None else
                       (lambda ev, _p=pi + 1, _n=len(paras):
                        on_progress(dict(ev, para=_p, para_n=_n))))
            part = os.path.join(wd, f"para_{pi}.wav")
            pns = _generate_unit(para, ref_wav, ref_text, ctx, part,
                                 fast=fast, takes=takes,
                                 on_progress=wrapped)
            pns_list.append(pns)
            y, sr_out = sf.read(part, dtype="float32")
            if y.ndim > 1:
                y = y.mean(axis=1)
            pieces.append(y)
        joined, t, paras_meta = [], 0.0, []
        for i, y in enumerate(pieces):
            if i:
                gap = float(rng.uniform(*PARA_GAP))
                joined.append(np.zeros(int(sr_out * gap), dtype="float32"))
                t += gap
            start = t
            t += len(y) / sr_out
            paras_meta.append({"text": paras[i], "start": round(start, 3),
                               "end": round(t, 3),
                               "pns": round(pns_list[i], 1)})
            joined.append(y)
        sf.write(output_path, np.concatenate(joined), sr_out)
    normalize_speech_level(output_path)
    avg = float(np.mean(pns_list))
    _notify(on_progress, stage="done", pns=round(avg, 1),
            paragraphs=paras_meta)
    return output_path, avg


def _generate_unit(text, ref_wav, ref_text, ctx, output_path,
                   fast=False, takes=DEFAULT_TAKES, on_progress=None):
    """한 문단(재사용 단위)의 테이크 생성→채점→선별→문장 조합.

    최적화: 생성(GPU, 상주 워커)과 채점(CPU: Whisper·pyin·UTMOS)을
    스레드로 오버랩 — 테이크 i를 채점하는 동안 테이크 i+1을 생성.
    채점 자체도 중복 제거: 문장 채점 1패스에서 어미낙하·먹힌단어를 파생.
    """
    from concurrent.futures import ThreadPoolExecutor
    from .prosody import (cliff_score, ending_metrics, ending_style_score,
                          evaluate_prosody, reshape_energy_contour,
                          stress_features, stress_style_score,
                          swallowed_score, take_sentence_scores,
                          word_drop_score)

    def score_take(take):
        sent_scores = take_sentence_scores(take, text)
        if sent_scores:
            wdrop = word_drop_score([s["drop"] for s in sent_scores])
            swallow = swallowed_score(min(s["swallow"] for s in sent_scores))
            gaps = [s["boundary_gap"] for s in sent_scores
                    if "boundary_gap" in s]
            from .prosody import boundary_pause_adequacy
            bpa = boundary_pause_adequacy(gaps) if gaps else None
        else:
            wdrop = swallow = 1.0
            bpa = None
        r = evaluate_prosody(ctx["wav"], take, script=text,
                             ref_feats=ctx["feats"], bpa=bpa)
        slopes, cliff_v = ending_metrics(take)
        ending = ending_style_score(slopes, ctx["slopes"])
        stress = stress_style_score(stress_features(take), ctx["stress"])
        cliff = cliff_score(cliff_v, ctx["cliff"])
        sel = (_selection_score(r["pns"], r["gen"]["artic_rate"], ctx["rate"])
               - ENDING_PENALTY * (1.0 - ending)
               - STRESS_PENALTY * (1.0 - stress)
               - CLIFF_PENALTY * (1.0 - cliff)
               - WORD_DROP_PENALTY * (1.0 - wdrop)
               - SWALLOW_PENALTY * (1.0 - swallow))
        return {"path": take, "pns": r["pns"], "sel": sel,
                "sent_scores": sent_scores,
                "detail": {"ending": ending, "stress": stress, "cliff": cliff,
                           "wdrop": wdrop, "swallow": swallow,
                           "rate": r["gen"]["artic_rate"]}}

    scored = []
    with tempfile.TemporaryDirectory() as wd, \
            ThreadPoolExecutor(max_workers=1) as pool:
        pending = None  # (future, index)
        stop = False
        for i in range(takes):
            take = os.path.join(wd, f"take_{i}.wav")
            _notify(on_progress, stage="take", i=i + 1, n=takes)
            synthesize(text, ref_wav, ref_text, take, fast=fast)
            ensure_breath_pauses(take, text)
            reshape_energy_contour(take, take)
            if pending is not None:  # 이전 테이크 채점 회수 (오버랩)
                res, idx = pending[0].result(), pending[1]
                scored.append(res)
                d = res["detail"]
                _notify(on_progress, stage="take_scored", i=idx + 1, n=takes,
                        pns=round(res["pns"], 1), sel=round(res["sel"], 1),
                        ending=round(d["ending"], 2),
                        stress=round(d["stress"], 2),
                        cliff=round(d["cliff"], 2),
                        wdrop=round(d["wdrop"], 2),
                        swallow=round(d["swallow"], 2),
                        rate=round(d["rate"], 1),
                        best=bool(pick_best_take(scored) == len(scored) - 1))
                if res["sel"] >= PNS_TARGET:
                    stop = True
            pending = (pool.submit(score_take, take), i)
            if stop:
                break
        if pending is not None:
            res, idx = pending[0].result(), pending[1]
            scored.append(res)
            d = res["detail"]
            _notify(on_progress, stage="take_scored", i=idx + 1, n=takes,
                    pns=round(res["pns"], 1), sel=round(res["sel"], 1),
                    ending=round(d["ending"], 2), stress=round(d["stress"], 2),
                    cliff=round(d["cliff"], 2), wdrop=round(d["wdrop"], 2),
                    swallow=round(d["swallow"], 2), rate=round(d["rate"], 1),
                    best=bool(pick_best_take(scored) == len(scored) - 1))
        best = scored[pick_best_take(scored)]
        composed = _compose_best_sentences(scored, text, output_path,
                                           on_progress=on_progress)
        if not composed:
            os.replace(best["path"], output_path)
    return best["pns"]


def _compose_best_sentences(scored, text, output_path, on_progress=None):
    """풀 테이크들에서 문장별 최고 구간을 골라 조합. 성공 시 True.

    문장이 2개 미만이거나, 어느 테이크든 문장 매핑이 실패하면 False
    (호출부가 통짜 베스트로 폴백). 문장 사이는 자연 호흡(0.5~0.7s) 삽입.
    """
    import numpy as np
    import soundfile as sf
    from .prosody import split_sentences, take_sentence_scores

    if len(split_sentences(text)) < 2 or len(scored) < 2:
        return False
    per_take = []
    for t in scored:
        s = t.get("sent_scores") or take_sentence_scores(t["path"], text)
        if s is None:
            return False
        per_take.append(s)
    k = len(per_take[0])
    if any(len(s) != k for s in per_take):
        return False

    rng = np.random.default_rng(len(text))
    pieces, sr_out, chosen = [], None, []
    for si in range(k):
        ti = max(range(len(per_take)), key=lambda t: per_take[t][si]["score"])
        chosen.append(ti + 1)
        a, b = per_take[ti][si]["span"]
        y, sr = sf.read(scored[ti]["path"], dtype="float32")
        if y.ndim > 1:
            y = y.mean(axis=1)
        sr_out = sr
        seg = y[max(0, int((a - 0.05) * sr)): int((b + 0.1) * sr)]
        fade = int(sr * 0.01)
        if len(seg) > 2 * fade:
            seg[:fade] *= np.linspace(0, 1, fade)
            seg[-fade:] *= np.linspace(1, 0, fade)
        pieces.append(seg)
    joined = [pieces[0]]
    for seg in pieces[1:]:
        gap = float(np.clip(rng.normal(0.6, 0.06), 0.5, 0.75))
        joined += [np.zeros(int(sr_out * gap), dtype="float32"), seg]
    sf.write(output_path, np.concatenate(joined), sr_out)
    _notify(on_progress, stage="composed", takes=chosen)
    return True


def clone_voice(ref_path, text, output_path, fast=False, takes=DEFAULT_TAKES,
                on_progress=None):
    """참조 파일 + 대본 → 클론 음성. 전체 파이프라인 한 번에. (앱 계층 진입점)"""
    with tempfile.TemporaryDirectory() as wd:
        _notify(on_progress, stage="reference")
        ref_wav, ref_text, full_clean = prepare_reference(ref_path, wd)
        _notify(on_progress, stage="reference_done", ref_text=ref_text)
        out, _ = synthesize_best(text, ref_wav, ref_text, full_clean,
                                 output_path, fast=fast, takes=takes,
                                 on_progress=on_progress)
        return out
