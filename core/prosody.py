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

    # ① F0 변동성 (세미톤 표준편차) — 억양의 살아있음
    f0 = librosa.pyin(y, fmin=_PYIN_FMIN, fmax=_PYIN_FMAX, sr=sr,
                      frame_length=1024)[0]
    f0v = f0[~np.isnan(f0)]
    if len(f0v) > 10:
        f0_st_std = float(np.std(12 * np.log2(f0v / np.median(f0v))))
    else:
        f0_st_std = 0.0

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
    #    로봇 발화 = 간격이 균일 = nPVI 낮음
    onsets = librosa.onset.onset_detect(y=y, sr=sr, units="time",
                                        backtrack=False)
    iois = np.diff(onsets)
    iois = iois[(iois > 0.05) & (iois < 1.0)]
    if len(iois) >= 3:
        pairs = 2 * np.abs(np.diff(iois)) / (iois[:-1] + iois[1:])
        npvi = float(100 * np.mean(pairs))
    else:
        npvi = 0.0

    return {"f0_st_std": f0_st_std, "pause_ratio": pause_ratio,
            "pause_rate": pause_rate, "npvi": npvi, "duration": dur}


def band_score(gen_val, ref_val, tolerance=0.3, floor_octaves=0.7):
    """로그 비율 밴드 스코어 (0~1). 참조값 대비 ±(tolerance×100)% 안이면 만점,
    벗어난 만큼 선형 감점, floor_octaves 옥타브(=2^0.7≈1.6배) 초과 이탈이면 0.
    순수 함수 — 유닛 테스트 대상."""
    g = max(float(gen_val), 1e-6)
    r = max(float(ref_val), 1e-6)
    x = abs(np.log2(g / r))
    allowed = np.log2(1 + tolerance)
    return float(np.clip(1 - max(0.0, x - allowed) / floor_octaves, 0.0, 1.0))


def prosody_match_scores(gen_feats, ref_feats):
    """참조 화자 자연 발화 대비 운율 일치도 3항 (각 0~1).

    통계 보정: 짧은 클립은 휴지가 1~2개뿐이라 비율 추정의 표본 변동이 크다
    (사람 발화 7초 구간도 ±30% 밴드에선 자주 이탈). 그래서 휴지·리듬 항의
    허용 밴드를 √(10초/길이) 배(최대 2배)로 넓힌다 — 표본 노이즈는 용서하되,
    실제 결함(휴지 전무, 2배 이상 이탈)은 여전히 감점되는 것을 검증했다."""
    dur = max(gen_feats.get("duration", 10.0), 1.0)
    scale = float(np.clip(np.sqrt(10.0 / dur), 1.0, 2.0))
    tol_stat = 0.3 * scale
    s_f0 = band_score(gen_feats["f0_st_std"], ref_feats["f0_st_std"])
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


def evaluate_prosody(ref_wav, gen_wav):
    """참조(자연 발화) 대비 생성물의 운율 자연스러움 종합 → dict."""
    ref_feats = prosody_features(ref_wav)
    gen_feats = prosody_features(gen_wav)
    match = prosody_match_scores(gen_feats, ref_feats)
    u = utmos(gen_wav)
    return {"pns": prosody_naturalness_score(u, match), "utmos": u,
            "match": match, "gen": gen_feats, "ref": ref_feats}


def prosody_deps_available():
    """PNS 계산에 필요한 선택 의존성(librosa, torch)이 있는지."""
    import importlib.util
    return all(importlib.util.find_spec(m) is not None
               for m in ("librosa", "torch"))


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
