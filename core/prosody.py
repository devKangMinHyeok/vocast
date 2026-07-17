"""운율(prosody) 정량화 + PNS(Prosody Naturalness Score, 북극성 지표).

문제 정의: 합성음이 "기계적"으로 들리는 원인은 문헌상 세 가지로 수렴한다 —
평평한 억양(F0 변동 부족), 지나치게 규칙적인 타이밍(리듬 변동 부족),
부자연스러운 호흡(휴지 분포 이탈). (TTS 운율 평가 체계적 리뷰, JBCS 2024:
F0·지속시간·휴지가 3대 파라미터. VoiceMOS 챌린지: UTMOS가 자연스러움
MOS 예측 표준.)

측정 원리 — 클로닝의 운율 목표 분포는 이론적으로 명확하다:
**참조 화자 본인의 자연 발화 운율 통계**. 그래서 각 항은 절대값이 아니라
"참조 음성과의 통계 일치도"로 채점한다 (밴드 스코어, 로그 비율 기반).

PNS = 100 × ( 0.4 × (UTMOS−1)/4        ← 인간 검증된 학습형 자연스러움
            + 0.2 × F0 변동 일치도      ← 억양이 참조 화자만큼 살아있는가
            + 0.2 × 휴지 패턴 일치도    ← 호흡 비율·빈도가 자연 분포인가
            + 0.2 × 리듬 변동 일치도 )  ← 타이밍이 로봇처럼 균일하지 않은가

UTMOS 가중치가 가장 큰 이유: 유일하게 사람 청취 평가로 검증된 항.
나머지는 리뷰 문헌의 3대 음향 파라미터에 균등 배분.
"""
import numpy as np

_PYIN_FMIN, _PYIN_FMAX = 65, 400  # Hz, 성인 발화 대역
PAUSE_MIN_SEC = 0.18   # 지각되는 휴지 최소 길이 (Campione & Véronis 2002: ~200ms)
PAUSE_DROP_DB = 25     # 발화 레벨 대비 이만큼 낮으면 무음으로 판정
_SR = 16_000

_utmos_model = None


def _load_utmos():
    global _utmos_model
    if _utmos_model is None:
        import torch
        _utmos_model = torch.hub.load(
            "tarepan/SpeechMOS:v1.2.0", "utmos22_strong", trust_repo=True,
            skip_validation=True)  # CI 러너에서 GitHub API 검증이 깨지는 torch.hub 버그 회피
    return _utmos_model


def utmos(wav_path):
    """UTMOS (1~5): VoiceMOS 챌린지 표준 자연스러움 MOS 예측."""
    import librosa
    import torch
    y, sr = librosa.load(wav_path, sr=_SR, mono=True)
    model = _load_utmos()
    with torch.no_grad():
        return float(model(torch.from_numpy(y).unsqueeze(0), sr))


def prosody_features(wav_path):
    """운율 특징 추출 → {f0_st_std, pause_ratio, pause_rate, npvi}."""
    import librosa
    y, sr = librosa.load(wav_path, sr=_SR, mono=True)
    y, _ = librosa.effects.trim(y, top_db=35)
    dur = len(y) / sr

    # ① F0 역동성 3종 — 억양의 살아있음 (세미톤 기준)
    #    std: 국소 변동 / span: 음역대(P10~P90) / move: 시간 창별 음높이
    #    중심의 이동(멜로디 움직임 — "일정하게만 말하는" 단조로움을 잡음)
    f0 = librosa.pyin(y, fmin=_PYIN_FMIN, fmax=_PYIN_FMAX, sr=sr,
                      frame_length=1024)[0]
    voiced = ~np.isnan(f0)
    f0v = f0[voiced]
    if len(f0v) > 10:
        st = 12 * np.log2(f0v / np.median(f0v))
        f0_st_std = float(np.std(st))
        f0_span_st = float(np.percentile(st, 90) - np.percentile(st, 10))
        # 0.5초 창별 유성음 F0 중앙값의 표준편차 (세미톤)
        frames_per_win = max(1, int(0.5 / (512 / sr)))  # pyin hop=512
        st_full = np.full(len(f0), np.nan)
        st_full[voiced] = st
        centers = []
        for w in range(0, len(st_full) - frames_per_win, frames_per_win):
            win = st_full[w: w + frames_per_win]
            win = win[~np.isnan(win)]
            if len(win) >= frames_per_win // 4:
                centers.append(np.median(win))
        f0_move = float(np.std(centers)) if len(centers) >= 3 else 0.0
    else:
        f0_st_std = f0_span_st = f0_move = 0.0

    # ② 휴지(호흡) 패턴 — 30ms 프레임 에너지로 무음 구간 검출
    hop = int(sr * 0.03)
    nf = len(y) // hop
    frames = y[: nf * hop].reshape(nf, hop)
    db = 20 * np.log10(np.maximum(np.sqrt((frames ** 2).mean(axis=1)), 1e-9))
    speech_level = np.percentile(db, 90)
    silent = db < (speech_level - PAUSE_DROP_DB)
    min_frames = max(1, int(PAUSE_MIN_SEC / 0.03))
    pause_time, pause_count, run = 0.0, 0, 0
    for s in np.append(silent, False):
        if s:
            run += 1
        else:
            if run >= min_frames:
                pause_time += run * 0.03
                pause_count += 1
            run = 0
    pause_ratio = pause_time / max(dur, 1e-6)
    pause_rate = pause_count / max(dur, 1e-6)

    # ③ 리듬 변동성 (onset 간격의 nPVI, Grabe & Low 2002) —
    #    로봇 발화 = 간격이 균일 = nPVI 낮음. 조음속도(음절핵/발화시간)도 함께.
    onsets = librosa.onset.onset_detect(y=y, sr=sr, units="time",
                                        backtrack=False)
    speech_time = max(dur - pause_time, 1e-6)
    artic_rate = len(onsets) / speech_time
    iois = np.diff(onsets)
    iois = iois[(iois > 0.05) & (iois < 1.0)]
    if len(iois) >= 3:
        pairs = 2 * np.abs(np.diff(iois)) / (iois[:-1] + iois[1:])
        npvi = float(100 * np.mean(pairs))
    else:
        npvi = 0.0

    return {"f0_st_std": f0_st_std, "f0_span_st": f0_span_st,
            "f0_move": f0_move, "pause_ratio": pause_ratio,
            "pause_rate": pause_rate, "npvi": npvi,
            "artic_rate": artic_rate, "duration": dur}


def band_score(gen_val, ref_val, tolerance=0.3, floor_octaves=0.7):
    """로그 비율 밴드 스코어 (0~1). 참조값 대비 ±(tolerance×100)% 안이면 만점,
    벗어난 만큼 선형 감점, floor_octaves 옥타브(=2^0.7≈1.6배) 초과 이탈이면 0.
    순수 함수 — 유닛 테스트 대상."""
    g = max(float(gen_val), 1e-6)
    r = max(float(ref_val), 1e-6)
    x = abs(np.log2(g / r))
    allowed = np.log2(1 + tolerance)
    return float(np.clip(1 - max(0.0, x - allowed) / floor_octaves, 0.0, 1.0))


LIVELINESS = 1.25  # 역동성 목표 계수 — 참조 화자의 차분한 녹음보다 이만큼 활기차게
# 활기 절대 상한 (세미톤): 이미 이 수준 이상으로 활기찬 화자는 자기 수준 유지.
# 근거: '활기찬 낭독' 실측치(사용자 목표 수준·표현력 있는 AI 프리셋 수준) 사이값.
LIVELY_CAPS = {"f0_st_std": 5.5, "f0_span_st": 13.5, "f0_move": 5.0}
TRANSFER_EFFICIENCY = 0.6  # 참조 증폭 → 출력 역동성 전달률 (실측 ~60%)


def dynamics_targets(ref_feats):
    """역동성 목표: 참조 × LIVELINESS, 단 절대 상한과 자기 수준 중 큰 값으로 캡.

    차분한 화자(예: 설명 톤 녹음)는 목표가 올라가고, 이미 활기찬 화자는
    자기 수준만 유지하면 된다. 순수 함수 — 유닛 테스트 대상.
    """
    targets = {}
    for k, cap in LIVELY_CAPS.items():
        r = max(float(ref_feats.get(k, 1e-6)), 1e-6)
        targets[k] = min(r * LIVELINESS, max(r, cap))
    return targets


def reference_exaggeration_alpha(natural_feats):
    """참조 증폭 계수 α를 필요한 만큼만 (적응적).

    필요 배율 = 목표/자연 수준의 평균. 전달률(~60%)을 보정해 α로 환산.
    이미 활기찬 화자는 α≈1 → 증폭 생략(보코더 처리 자체를 건너뜀).
    """
    targets = dynamics_targets(natural_feats)
    ratios = [targets[k] / max(float(natural_feats.get(k, 1e-6)), 1e-6)
              for k in LIVELY_CAPS]
    needed = float(np.mean(ratios))
    return float(np.clip(1.0 + (needed - 1.0) / TRANSFER_EFFICIENCY, 1.0, 1.7))


def dynamics_score(gen_val, ref_val, full_credit_at=0.85):
    """F0 역동성 비대칭 스코어 (0~1). 목표 대비 부족은 강하게 벌점,
    약간의 초과(1.6배까지)는 허용 — 청취 피드백('높낮이가 더 있었으면')과
    문헌('활기찰수록 F0 변동이 큼')의 방향성. full_credit_at은 짧은 클립의
    통계 변동 보정용(호출부에서 길이에 따라 완화). 순수 함수."""
    g = max(float(gen_val), 1e-6)
    r = max(float(ref_val), 1e-6)
    ratio = g / r
    if ratio < full_credit_at:  # 부족: 감점, 0.35배에서 0점
        return float(np.clip((ratio - 0.35) / (full_credit_at - 0.35), 0.0, 1.0))
    if ratio <= 1.6:   # 자연 범위
        return 1.0
    return float(np.clip(1.0 - (ratio - 1.6) / 1.4, 0.0, 1.0))  # 과장: 3배에서 0점


def prosody_match_scores(gen_feats, ref_feats):
    """참조 화자 자연 발화 대비 운율 일치도 3항 (각 0~1).

    통계 보정: 짧은 클립은 휴지가 1~2개뿐이라 비율 추정의 표본 변동이 크다
    (사람 발화 7초 구간도 ±30% 밴드에선 자주 이탈). 그래서 휴지·리듬 항의
    허용 밴드를 √(10초/길이) 배(최대 2배)로 넓힌다 — 표본 노이즈는 용서하되,
    실제 결함(휴지 전무, 2배 이상 이탈)은 여전히 감점되는 것을 검증했다."""
    dur = max(gen_feats.get("duration", 10.0), 1.0)
    scale = float(np.clip(np.sqrt(10.0 / dur), 1.0, 2.0))
    tol_stat = 0.3 * scale
    # F0 항 = 역동성 3종(std·span·move)의 비대칭 스코어 평균.
    # 목표는 dynamics_targets (참조×활기 계수, 절대 상한 캡).
    # 짧은 클립은 F0 통계 표본도 적으므로 만점 문턱을 길이에 따라 완화.
    targets = dynamics_targets(ref_feats)
    full_credit = max(0.75, 0.85 - 0.1 * (scale - 1.0))
    s_f0 = float(np.mean([
        dynamics_score(gen_feats.get(k, 0), targets[k],
                       full_credit_at=full_credit) for k in LIVELY_CAPS
    ]))
    s_pause = 0.5 * (band_score(gen_feats["pause_ratio"], ref_feats["pause_ratio"],
                                tolerance=tol_stat)
                     + band_score(gen_feats["pause_rate"], ref_feats["pause_rate"],
                                  tolerance=tol_stat))
    s_rhythm = band_score(gen_feats["npvi"], ref_feats["npvi"], tolerance=tol_stat)
    return {"f0": s_f0, "pause": s_pause, "rhythm": s_rhythm}


def prosody_naturalness_score(utmos_val, match):
    """PNS (0~100). 순수 함수 — 유닛 테스트 대상."""
    u = (min(max(utmos_val, 1.0), 5.0) - 1.0) / 4.0
    return 100.0 * (0.4 * u + 0.2 * match["f0"]
                    + 0.2 * match["pause"] + 0.2 * match["rhythm"])


def evaluate_prosody(ref_wav, gen_wav, script=None):
    """참조(자연 발화) 대비 생성물의 운율 자연스러움 종합 → dict.

    script를 주면 문장 경계 호흡(BPA)을 측정해 휴지 항에 반영한다:
    휴지 항 = 0.5 × 전역 휴지 일치 + 0.5 × BPA. ("문장을 붙여 읽는" 결함은
    전역 통계로는 안 잡히고 경계 위치 측정으로만 잡힌다 — 실측 검증.)
    """
    ref_feats = prosody_features(ref_wav)
    gen_feats = prosody_features(gen_wav)
    match = prosody_match_scores(gen_feats, ref_feats)
    bpa = None
    if script and len(split_sentences(script)) >= 2:
        bpa = boundary_pause_adequacy(sentence_boundary_gaps(gen_wav, script))
        match["pause"] = 0.5 * match["pause"] + 0.5 * bpa
    u = utmos(gen_wav)
    return {"pns": prosody_naturalness_score(u, match), "utmos": u, "bpa": bpa,
            "match": match, "gen": gen_feats, "ref": ref_feats}


# ---- 문장 경계 호흡 (BPA) ----
# 근거: 읽기 발화의 문장 경계 휴지 중앙값 ~400ms(IQR 250~500ms),
# 경계 휴지 임계 ~200ms, 상한 ~1초 (Campione & Véronis 2002 외).
BREATH_MIN, BREATH_MAX = 0.35, 1.2  # 자연 범위 (초)


def split_sentences(text):
    """대본을 문장으로 분할 (순수 함수)."""
    import re
    parts = re.split(r"(?<=[.!?…])\s+", text.strip())
    return [p for p in parts if p]


# (긴 대본 청크 분할 생성은 실측 기각 — core/clone.py 주석 참고.
#  이 모델은 긴 글을 통째로 읽을 때 페이스·리듬이 가장 자연스럽다.)


def final_f0_slopes(wav_path):
    """발화 조각(≥0.25s 무음으로 구분)마다 끝 0.4초의 F0 기울기(st/s) 목록.

    끝음 처리의 정량화: 평서문은 F0 하강이 전형이지만(문헌), 화자마다
    스타일이 다르다 — 실측: 사용자(에너지 있는 유튜버 톤)는 중앙값 +2.0st/s
    (상승/유지형), 클론은 -3.5~-4.3(낭독체 하강) → "끝음이 AI 같다"의 실체.
    """
    import librosa
    y, sr = librosa.load(wav_path, sr=_SR, mono=True)
    y, _ = librosa.effects.trim(y, top_db=35)
    f0 = librosa.pyin(y, fmin=_PYIN_FMIN, fmax=_PYIN_FMAX, sr=sr,
                      frame_length=1024)[0]
    hop_t = 512 / sr
    voiced = ~np.isnan(f0)
    st = np.full(len(f0), np.nan)
    if voiced.sum() > 10:
        st[voiced] = 12 * np.log2(f0[voiced] / np.nanmedian(f0[voiced]))
    hop = int(sr * 0.03)
    nf = len(y) // hop
    db = 20 * np.log10(np.maximum(
        np.sqrt((y[: nf * hop].reshape(nf, hop) ** 2).mean(axis=1)), 1e-9))
    silent = db < np.percentile(db, 90) - PAUSE_DROP_DB
    ends, run = [], 0
    min_run = int(0.25 / 0.03)
    for i, s in enumerate(np.append(silent, True)):
        run = run + 1 if s else 0
        if run == min_run and i * 0.03 > 1.0:
            ends.append((i - run + 1) * 0.03)
    slopes = []
    for t_end in ends:
        i1 = int(t_end / hop_t)
        i0 = max(0, i1 - int(0.4 / hop_t))
        seg = st[i0:i1]
        idx = np.where(~np.isnan(seg))[0]
        if len(idx) >= 5:
            slopes.append(float(np.polyfit(idx * hop_t, seg[idx], 1)[0]))
    return slopes


def stress_features(wav_path):
    """음절 강약 특징: 피크 레벨 범위(강세 구조) + 피크-밸리 대비(분절 깊이).

    문헌: 음절 prominence의 음향 상관물은 강도·에너지 범위·지속시간.
    실측 변별 — 사람: 피크범위 17~18dB(강조/흘림의 대비가 큼), 대비 16~18dB.
    클론: 피크범위 13~16dB(균일한 강세), 대비 20~23dB(모든 음절을 또박또박
    과분절) → "음절 강약이 AI 같다"의 실체.
    """
    import librosa
    from scipy.signal import find_peaks
    y, sr = librosa.load(wav_path, sr=_SR, mono=True)
    y, _ = librosa.effects.trim(y, top_db=35)
    env = librosa.feature.rms(y=y, frame_length=400, hop_length=160)[0]
    db = 20 * np.log10(np.maximum(env, 1e-6))
    th = np.percentile(db, 90) - 30
    peaks, _ = find_peaks(db, distance=9, height=th)  # 음절핵 근사 (≥90ms 간격)
    if len(peaks) < 6:
        return None
    peak_db = db[peaks]
    contrasts = []
    for a, b in zip(peaks[:-1], peaks[1:]):
        valley = db[a:b].min()
        contrasts.append(((db[a] - valley) + (db[b] - valley)) / 2)
    return {"peak_range": float(np.percentile(peak_db, 90)
                                - np.percentile(peak_db, 10)),
            "peak_valley": float(np.mean(contrasts))}


def stress_style_score(gen_feats, ref_feats):
    """강약 스타일 일치도 (0~1). 순수 함수.

    피크범위는 부족을(강세 구조 없음), 피크-밸리는 과다를(과분절) 벌점.
    """
    if not gen_feats or not ref_feats:
        return 1.0
    s_range = dynamics_score(gen_feats["peak_range"], ref_feats["peak_range"])
    s_valley = dynamics_score(ref_feats["peak_valley"],
                              gen_feats["peak_valley"])  # 방향 반전: 과다 벌점
    return float(0.5 * (s_range + s_valley))


def ending_style_score(gen_slopes, ref_slopes, tolerance=2.0, floor=8.0):
    """끝음 스타일 일치도 (0~1): 끝음 기울기 중앙값의 화자 대비 차이.

    tolerance(st/s) 이내면 만점, floor 초과 이탈이면 0점. 순수 함수."""
    if not gen_slopes or not ref_slopes:
        return 1.0
    diff = abs(float(np.median(gen_slopes)) - float(np.median(ref_slopes)))
    return float(np.clip(1.0 - max(0.0, diff - tolerance) / floor, 0.0, 1.0))


def _normalize_chars(text):
    import re
    return re.sub(r"[^\w]", "", text, flags=re.UNICODE).lower()


def sentence_boundary_gaps(wav_path, script):
    """대본의 문장 경계마다 오디오에서 실제 휴지 길이(초)를 측정. 문장 1개면 []."""
    return [b["gap"] for b in sentence_boundary_info(wav_path, script)]


def sentence_boundary_info(wav_path, script):
    """문장 경계 상세: [{gap, insert_at, silence:(s,e)|None}, ...].

    Whisper 단어 타임스탬프를 대본과 문자 단위 정렬(difflib)해 경계 위치를
    잡고, 휴지 길이는 에너지 기반 무음 검출로 잰다 (Whisper의 단어 종료
    시각은 무음을 삼키는 경향이 있음 — 실측). insert_at은 호흡을 삽입하기에
    적절한 시각(기존 무음의 중앙, 없으면 다음 단어 시작 직전).
    """
    import difflib
    import mlx_whisper
    from .clone import WHISPER

    sents = split_sentences(script)
    if len(sents) < 2:
        return []
    r = mlx_whisper.transcribe(wav_path, path_or_hf_repo=WHISPER,
                               language="ko", word_timestamps=True)
    words = [w for seg in r["segments"] for w in seg["words"]]
    if len(words) < 2:
        return []

    # 전사 단어들의 정규화 문자열과 각 문자의 단어 인덱스 매핑
    hyp_chars, hyp_word_idx = [], []
    for i, w in enumerate(words):
        for ch in _normalize_chars(w["word"]):
            hyp_chars.append(ch)
            hyp_word_idx.append(i)
    hyp_str = "".join(hyp_chars)

    # 대본 정규화 문자열과 문장 경계의 문자 위치
    ref_str, cut_positions = "", []
    for s in sents[:-1]:
        ref_str += _normalize_chars(s)
        cut_positions.append(len(ref_str) - 1)  # 문장 마지막 문자 위치
    ref_str += _normalize_chars(sents[-1])

    sm = difflib.SequenceMatcher(None, ref_str, hyp_str, autojunk=False)
    # ref 문자 위치 → hyp 문자 위치 매핑
    ref2hyp = {}
    for a, b, n in sm.get_matching_blocks():
        for k in range(n):
            ref2hyp[a + k] = b + k

    silence_runs = _silence_runs(wav_path)

    infos = []
    for pos in cut_positions:
        # 경계 근처에서 매칭된 문자 찾기 (±5자 탐색)
        hyp_pos = None
        for d in range(6):
            if pos - d in ref2hyp:
                hyp_pos = ref2hyp[pos - d]
                break
        if hyp_pos is None:
            continue
        wi = hyp_word_idx[hyp_pos]
        if wi + 1 >= len(words):
            continue
        lo = float(words[wi]["start"])
        hi = float(words[wi + 1]["end"])
        # 경계 구간과 겹치는 무음 중 가장 긴 것 = 그 경계의 호흡
        best, best_run = 0.0, None
        for s, e in silence_runs:
            if s < hi and e > lo and (e - s) > best:
                best, best_run = e - s, (s, e)
        insert_at = ((best_run[0] + best_run[1]) / 2 if best_run
                     else max(float(words[wi + 1]["start"]) - 0.02, lo))
        infos.append({"gap": best, "insert_at": insert_at,
                      "silence": best_run})
    return infos


def _silence_runs(wav_path, min_sec=0.12):
    """에너지 기반 무음 구간 목록 → [(시작초, 끝초), ...]."""
    import librosa
    y, sr = librosa.load(wav_path, sr=_SR, mono=True)
    hop = int(sr * 0.03)
    nf = len(y) // hop
    db = 20 * np.log10(np.maximum(
        np.sqrt((y[: nf * hop].reshape(nf, hop) ** 2).mean(axis=1)), 1e-9))
    th = np.percentile(db, 90) - PAUSE_DROP_DB
    silent = db < th
    runs, start = [], None
    for i, s in enumerate(np.append(silent, False)):
        if s and start is None:
            start = i
        elif not s and start is not None:
            if (i - start) * 0.03 >= min_sec:
                runs.append((start * 0.03, i * 0.03))
            start = None
    return runs


def boundary_pause_adequacy(gaps):
    """BPA (0~1): 문장 경계 휴지가 자연 범위[BREATH_MIN, BREATH_MAX]에 드는 정도.

    경계가 없으면(단문) 1.0. 부족하면 gap/MIN 비례 감점, 과다하면 2초에서 0점.
    순수 함수 — 유닛 테스트 대상.
    """
    if not gaps:
        return 1.0
    scores = []
    for g in gaps:
        if g < BREATH_MIN:
            scores.append(g / BREATH_MIN)
        elif g <= BREATH_MAX:
            scores.append(1.0)
        else:
            scores.append(max(0.0, 1.0 - (g - BREATH_MAX) / (2.0 - BREATH_MAX)))
    return float(np.mean(scores))


def prosody_deps_available():
    """PNS 계산에 필요한 선택 의존성(librosa, torch)이 있는지."""
    import importlib.util
    return all(importlib.util.find_spec(m) is not None
               for m in ("librosa", "torch"))


def exaggerate_pitch(in_wav, out_wav, alpha):
    """WORLD 보코더로 F0 편차를 α배 증폭 (음색·중심 음높이는 유지).

    출력이 아니라 **참조 음성**에 쓴다 — 출력에 직접 쓰면 보코더 아티팩트로
    UTMOS가 3.95→3.2로 폭락(실측 기각). 참조에 쓰면 클론이 억양만 물려받고
    오디오는 순수 TTS 생성이라 깨끗하다 (실측: UTMOS -0.14, 역동성 목표 도달).
    """
    import librosa
    import pyworld
    import soundfile as sf
    y, sr = librosa.load(in_wav, sr=24_000, mono=True)
    y = y.astype(np.float64)
    f0, t = pyworld.harvest(y, sr)
    sp = pyworld.cheaptrick(y, f0, t, sr)
    ap = pyworld.d4c(y, f0, t, sr)
    voiced = f0 > 0
    if not voiced.any():
        sf.write(out_wav, y.astype(np.float32), sr)
        return out_wav
    med = np.median(f0[voiced])
    f0_new = f0.copy()
    f0_new[voiced] = med * (f0[voiced] / med) ** alpha
    out = pyworld.synthesize(f0_new, sp, ap, sr)
    peak = np.abs(out).max()
    if peak > 0:
        out = out / peak * np.abs(y).max()
    sf.write(out_wav, out.astype(np.float32), sr)
    return out_wav


def select_reference_window(full_wav, min_sec=6.0, max_sec=14.0):
    """자연 녹음에서 클로닝 참조로 쓸 최적 창 선택 → (시작초, 끝초).

    원칙 두 가지 (후보 경쟁 실측으로 검증):
    1. 창 경계를 휴지(무음) 중앙에 스냅 — 문장이 중간에 잘리면 참조 텍스트와
       오디오가 어긋나 생성 앞부분에 참조 꼬리가 새어 들어온다 (CER 17.9% 사고).
    2. 억양(F0 변동)이 살아있고 자연 휴지가 있는 창 선호 — 클론은 참조의
       운율을 물려받는다.
    """
    import librosa
    y, sr = librosa.load(full_wav, sr=_SR, mono=True)
    hop = int(sr * 0.03)
    nf = len(y) // hop
    db = 20 * np.log10(np.maximum(
        np.sqrt((y[: nf * hop].reshape(nf, hop) ** 2).mean(axis=1)), 1e-9))
    th = np.percentile(db, 90) - PAUSE_DROP_DB
    silent = db < th
    cuts, run_start = [0.0], None
    for i, s in enumerate(np.append(silent, False)):
        if s and run_start is None:
            run_start = i
        elif not s and run_start is not None:
            if (i - run_start) * 0.03 >= PAUSE_MIN_SEC:
                cuts.append((run_start + i) / 2 * 0.03)
            run_start = None
    cuts.append(len(y) / sr)

    import soundfile as sf
    import tempfile
    best, best_score = None, -1.0
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        for i in range(len(cuts)):
            for j in range(i + 1, len(cuts)):
                dur = cuts[j] - cuts[i]
                if not (min_sec <= dur <= max_sec):
                    continue
                sf.write(tmp.name, y[int(cuts[i] * sr): int(cuts[j] * sr)], sr)
                f = prosody_features(tmp.name)
                if f["f0_st_std"] == 0:
                    continue
                score = f["f0_st_std"] * (1 + min(f["pause_rate"], 0.5))
                if score > best_score:
                    best_score, best = score, (cuts[i], cuts[j])
    if best is None:  # 녹음이 너무 짧거나 무음뿐이면 앞부분 사용
        return 0.0, min(max_sec, len(y) / sr)
    return best
