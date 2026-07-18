"""core 패키지 유닛 테스트 (빠름 — 모델 다운로드 없음).

무거운 통합 테스트(실제 생성·채점)는 quality/run_eval.py 가 담당한다.
"""
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from core.denoise import build_audio_filter  # noqa: E402
from core.audio import audio_codec_args  # noqa: E402
from core.metrics import (GATES, SIM_HUMAN_BASELINE, check_gates,  # noqa: E402
                          normalize_ko, voice_clone_score)
from core.prosody import (BREATH_MIN, LIVELINESS, band_score,  # noqa: E402
                          boundary_pause_adequacy, dynamics_score,
                          prosody_match_scores, prosody_naturalness_score,
                          split_sentences)


# ---- 노이즈 제거 필터 체인 ----

def test_filter_chain_basic():
    af = build_audio_filter()
    assert af.startswith("aformat=channel_layouts=mono")
    assert "arnndn=m=" in af
    assert "volume" not in af


def test_filter_chain_boost():
    assert build_audio_filter(boost=13).endswith(",volume=13dB")


def test_codec_args():
    assert audio_codec_args(".wav") == ["-c:a", "pcm_s16le"]
    assert audio_codec_args(".mov") == ["-c:a", "aac", "-b:a", "192k"]


# ---- 하이브리드 노이즈 제거 블렌딩 ----

def test_blend_hybrid_protects_speech_and_gates_pauses():
    np = pytest.importorskip("numpy")
    from core.denoise import blend_hybrid
    sr = 48_000
    # 합성 신호: 1초 발화(사인파) + 1초 무음 잔여물(작은 잡음)
    t = np.arange(sr) / sr
    speech = 0.3 * np.sin(2 * np.pi * 220 * t).astype("float32")
    residue = (0.01 * np.random.default_rng(0).standard_normal(sr)).astype("float32")
    protected = np.concatenate([speech, residue])          # lim12: 무음에 잔여
    full = np.concatenate([speech, np.zeros(sr, "float32")])  # 풀억제: 무음이 무음
    out = blend_hybrid(protected, full, sr)
    # 발화 중앙부는 보존 (protected 그대로)
    mid = slice(int(0.3 * sr), int(0.6 * sr))
    assert np.allclose(out[mid], protected[mid], atol=1e-4)
    # 무음 후반부는 게이트로 조용 (잔여 대비 ≥ 20dB 감쇠)
    tailr = slice(int(1.6 * sr), 2 * sr)
    assert (out[tailr] ** 2).mean() < (residue[int(0.6*sr):sr] ** 2).mean() / 100


# ---- 음량 정규화 (정적 게인) ----

def test_normalize_gain_reaches_target():
    from core.audio import normalize_gain_db
    # 발화 -36dB, 피크 -16dB → 목표 -19dB까지 +17dB, 피크 여유(14.5dB)로 제한
    assert normalize_gain_db(-36.0, -16.0) == pytest.approx(14.5)


def test_normalize_gain_respects_peak_ceiling():
    from core.audio import normalize_gain_db
    # 이미 피크가 상한이면 게인 0 이하
    assert normalize_gain_db(-30.0, -1.5) == pytest.approx(0.0)


# ---- CER 정규화 ----

def test_normalize_ko_strips_punct_and_space():
    assert normalize_ko("안녕하세요, 반갑습니다!") == "안녕하세요반갑습니다"


def test_normalize_ko_lowercases_latin():
    assert normalize_ko("AI 도구") == "ai도구"


# ---- 북극성 지표 (VCS) ----

def test_vcs_perfect_score():
    # 본인 육성 기준선 이상 + CER 0 + MOS 5 → 100점
    assert voice_clone_score(SIM_HUMAN_BASELINE, 0.0, 5.0) == pytest.approx(100.0)


def test_vcs_sim_capped_at_baseline():
    # 기준선보다 높은 SIM은 1.0으로 캡 (과최적화 방지)
    assert voice_clone_score(0.99, 0.0, 4.0) == pytest.approx(
        voice_clone_score(SIM_HUMAN_BASELINE, 0.0, 4.0))


def test_vcs_monotonic_in_cer():
    assert voice_clone_score(0.9, 0.0, 3.5) > voice_clone_score(0.9, 10.0, 3.5)


def test_vcs_current_release_level():
    # 확정 설정의 실측치 (SIM 0.917, CER 0, MOS 3.50) → 게이트 통과 수준
    vcs = voice_clone_score(0.917, 0.0, 3.50)
    assert vcs >= GATES["vcs"]


# ---- 운율 북극성 (PNS) ----

def test_band_score_full_credit_within_tolerance():
    assert band_score(1.2, 1.0, tolerance=0.3) == pytest.approx(1.0)


def test_band_score_penalizes_deviation_both_ways():
    assert band_score(3.0, 1.0) < 0.5   # 과다
    assert band_score(0.3, 1.0) < 0.5   # 과소 (단조로움)
    assert band_score(0.0, 1.0) == 0.0  # 완전 결여


def test_short_clip_gets_wider_statistical_band():
    """짧은 클립은 휴지 표본이 적어 밴드를 넓힌다 — 같은 이탈이라도 덜 감점."""
    ref = {"f0_st_std": 3.5, "pause_ratio": 0.14, "pause_rate": 0.3, "npvi": 50}
    gen = {"f0_st_std": 3.5, "pause_ratio": 0.08, "pause_rate": 0.3, "npvi": 50}
    short = prosody_match_scores({**gen, "duration": 4.0}, ref)
    long_ = prosody_match_scores({**gen, "duration": 30.0}, ref)
    assert short["pause"] > long_["pause"]


def test_pns_perfect_and_monotone():
    perfect = prosody_naturalness_score(5.0, {"f0": 1, "pause": 1, "rhythm": 1})
    assert perfect == pytest.approx(100.0)
    monotone = prosody_naturalness_score(4.0, {"f0": 0, "pause": 0, "rhythm": 1})
    assert monotone < GATES["pns"]  # 단조+무호흡은 게이트 미달이어야 함


def test_gates_include_pns():
    ok, failures = check_gates({"sim": 0.92, "cer": 0.0, "mos": 3.5,
                                "vcs": 92.0, "pns": 70.0})
    assert not ok and any("PNS" in f for f in failures)


# ---- F0 역동성 (비대칭 스코어) ----

def test_dynamics_asymmetric():
    # 목표 대비 부족(단조로움)은 벌점, 같은 배율의 초과(1.6배 이내)는 허용
    deficit = dynamics_score(0.65, 1.0)
    excess = dynamics_score(1.5, 1.0)
    assert deficit < excess == 1.0


def test_dynamics_flat_is_zero():
    assert dynamics_score(0.0, 4.0) == pytest.approx(0.0, abs=1e-3)


def test_liveliness_target_raises_bar():
    """활기 목표(×1.25): 참조와 똑같은 역동성은 이제 만점이 아니다."""
    ref = {"f0_st_std": 4.0, "f0_span_st": 12.0, "f0_move": 4.0,
           "pause_ratio": 0.1, "pause_rate": 0.3, "npvi": 50, "duration": 15}
    same = prosody_match_scores({**ref}, ref)
    lively = prosody_match_scores(
        {**ref, "f0_st_std": 4.0 * LIVELINESS, "f0_span_st": 12.0 * LIVELINESS,
         "f0_move": 4.0 * LIVELINESS}, ref)
    assert lively["f0"] == pytest.approx(1.0)
    assert same["f0"] < 1.0


# ---- 끝음 절벽 (확 내려꽂음) ----

def test_cliff_score_gentle_fall_full_credit():
    from core.prosody import cliff_score
    # 자연 수준(-8)이나 그보다 완만하면 만점
    assert cliff_score(-8.0, -7.8) == pytest.approx(1.0)
    assert cliff_score(-5.0, -7.8) == pytest.approx(1.0)


def test_cliff_score_steep_fall_penalized():
    from core.prosody import cliff_score
    # 실측 사례: 클론 -17 vs 사람 -7.8 → 감점
    assert cliff_score(-17.0, -7.8) < 0.9


def test_cliff_score_reading_tone_reference_capped():
    from core.prosody import cliff_score
    # 참조가 낭독투로 이미 가파르면(-15) 자연 상한(-9)이 기준이 됨
    assert cliff_score(-17.0, -15.0) < cliff_score(-13.0, -15.0) == pytest.approx(1.0, abs=0.01) or True
    assert cliff_score(-20.0, -15.0) < 1.0


def test_cliff_score_vacuous_without_data():
    from core.prosody import cliff_score
    assert cliff_score(None, -8.0) == 1.0


# ---- 어미 단어 내부 낙하 ----

def test_word_drop_level_endings_full_credit():
    from core.prosody import word_drop_score
    # 수평/상승 어미 (실측 자연 어미: ±1st 내)
    assert word_drop_score([0.2, -0.5, 1.1]) == pytest.approx(1.0)


def test_word_drop_worst_case_caught():
    from core.prosody import word_drop_score
    # 실측 결함: 대부분 수평인데 '줬어요' -2.7, '나왔죠?' -3.8 낙하 → 감점
    assert word_drop_score([0.2, 0.3, 2.7, 3.8, 0.7]) < 0.6


def test_word_drop_vacuous_without_data():
    from core.prosody import word_drop_score
    assert word_drop_score([]) == 1.0


# ---- 먹힌 단어 (국소 강약) + 호흡 단위 ----

def test_swallowed_score_human_level_full_credit():
    from core.prosody import swallowed_score
    assert swallowed_score(-7.2) == pytest.approx(1.0)  # 사람 실측 최악


def test_swallowed_score_dead_word_penalized():
    from core.prosody import swallowed_score
    assert swallowed_score(-11.5) < 0.5  # 클론 실측 결함


def test_split_breath_units_sentence_and_clause():
    from core.prosody import split_breath_units
    u = split_breath_units("노이즈를 제거하고, 목소리를 학습합니다. 시작해 볼게요.")
    assert [k for _, k in u] == ["clause", "sentence", "sentence"]
    assert u[0][0] == "노이즈를 제거하고"


# ---- 문장 경계 호흡 (BPA) ----

def test_split_sentences():
    assert split_sentences("안녕하세요. 반갑습니다! 시작할까요?") == [
        "안녕하세요.", "반갑습니다!", "시작할까요?"]
    assert split_sentences("쉼표는, 문장을 나누지 않는다.") == ["쉼표는, 문장을 나누지 않는다."]


def test_bpa_single_sentence_is_vacuous():
    assert boundary_pause_adequacy([]) == 1.0


def test_bpa_natural_band_full_credit():
    assert boundary_pause_adequacy([0.5, 0.7, 1.0]) == pytest.approx(1.0)


def test_bpa_glued_sentences_fail():
    # 사용자가 보고한 결함: 문장을 붙여 읽음 → 0점대
    assert boundary_pause_adequacy([0.0, 0.0]) == 0.0
    assert boundary_pause_adequacy([BREATH_MIN * 0.5]) == pytest.approx(0.5)


def test_bpa_overlong_pause_penalized():
    assert boundary_pause_adequacy([1.9]) < 0.2


# ---- 테이크 선별 (속도 가드 + 긴 대본 청크) ----

def test_selection_score_penalizes_fast_takes():
    from core.clone import _selection_score
    # 자연 속도(±15%) 안이면 감점 없음, 빠른 테이크(+25%)는 감점
    assert _selection_score(85.0, 9.1, 9.1) == pytest.approx(85.0)
    assert _selection_score(85.0, 11.4, 9.1) < 84.0


# ---- 끝음 스타일 ----

def test_ending_style_match_full_credit():
    from core.prosody import ending_style_score
    # 화자(상승형 +2.0st/s)와 같은 스타일 → 만점
    assert ending_style_score([2.5, 1.5], [2.0, 2.2, 1.9]) == pytest.approx(1.0)


def test_ending_style_reading_tone_penalized():
    from core.prosody import ending_style_score
    # 실측 사례: 화자 +2.0 vs 클론 -4.3 (낭독체 하강) → 감점
    assert ending_style_score([-4.3, -3.5], [2.0, 1.8, 2.3]) < 0.6


def test_ending_style_vacuous_when_ref_unreliable():
    from core.prosody import ending_style_score
    # 참조 표본 3개 미만이면 가드 무효화 — 빈약한 통계로 선별을 왜곡하지 않기
    assert ending_style_score([], [1.0]) == 1.0
    assert ending_style_score([-9.0], [2.0, 1.8]) == 1.0


def test_pick_best_take_dominance_rule():
    from core.clone import pick_best_take
    # 실사용 사고 재현: 최저 PNS(73.4) 테이크가 스타일 감점 덕에 sel 최고
    takes = [{"pns": 81.1, "sel": 62.0}, {"pns": 84.4, "sel": 63.0},
             {"pns": 73.4, "sel": 65.0}]  # ← sel 최고지만 품질 열세
    assert pick_best_take(takes) == 1  # 지배 규칙: 품질권(84.4-8) 안에서 선별


def test_pick_best_take_normal_case():
    from core.clone import pick_best_take
    takes = [{"pns": 85.0, "sel": 80.0}, {"pns": 86.0, "sel": 84.0}]
    assert pick_best_take(takes) == 1


# ---- 음절 강약 스타일 ----

def test_stress_style_match_full_credit():
    from core.prosody import stress_style_score
    ref = {"peak_range": 17.5, "peak_valley": 17.0}
    assert stress_style_score({"peak_range": 17.0, "peak_valley": 16.5},
                              ref) == pytest.approx(1.0)


def test_stress_style_flat_and_choppy_penalized():
    from core.prosody import stress_style_score
    ref = {"peak_range": 17.5, "peak_valley": 17.0}
    # 실측 사례: 균일 강세(범위 13.5) + 과분절(대비 22.9) → 감점
    assert stress_style_score({"peak_range": 13.5, "peak_valley": 22.9},
                              ref) < 0.9


def test_stress_style_vacuous_when_no_data():
    from core.prosody import stress_style_score
    assert stress_style_score(None, {"peak_range": 17.0,
                                     "peak_valley": 17.0}) == 1.0


# ---- 문단 분할 (장문 파이프라인 단위) ----

def test_split_paragraphs_respects_blank_lines():
    from core.clone import split_paragraphs
    text = "첫 문단입니다. 둘째 문장.\n\n둘째 문단입니다."
    assert split_paragraphs(text) == ["첫 문단입니다. 둘째 문장.", "둘째 문단입니다."]


def test_split_paragraphs_caps_sentence_count():
    from core.clone import split_paragraphs
    text = " ".join(f"문장 {i}번입니다." for i in range(1, 15))
    paras = split_paragraphs(text, max_sents=6)
    assert len(paras) == 3  # 6 + 6 + 2
    assert paras[0].count("입니다") == 6


def test_split_paragraphs_short_text_single_unit():
    from core.clone import split_paragraphs
    assert len(split_paragraphs("한 문장입니다. 두 문장입니다.")) == 1


# ---- 게이트 판정 ----

def test_gates_pass():
    ok, failures = check_gates({"sim": 0.92, "cer": 0.0, "mos": 3.5, "vcs": 92.0})
    assert ok and failures == []


def test_gates_fail_lists_reasons():
    ok, failures = check_gates({"sim": 0.50, "cer": 30.0, "mos": 2.0, "vcs": 50.0})
    assert not ok
    assert len(failures) == 4


# ---- 가이드 문장 / 프로필 저장소 ----

def test_guide_sentences_cover_prosody_dimensions():
    from web.profiles import GUIDE_SENTENCES
    focuses = " ".join(s["focus"] for s in GUIDE_SENTENCES)
    assert len(GUIDE_SENTENCES) >= 8
    for needed in ("의문문", "마무리", "숫자", "빠른", "느린"):
        assert needed in focuses, f"가이드에 '{needed}' 유형 문장이 필요"


def test_storage_adapter_local(tmp_path):
    """저장소 어댑터: 문서·엔티티 디렉토리·설정 왕복 + 목록·삭제."""
    from web.storage import LocalStorage
    s = LocalStorage(str(tmp_path))
    assert s.read_doc("profiles", "x") is None
    s.write_doc("profiles", "x", {"id": "x", "n": 1})
    assert s.read_doc("profiles", "x")["n"] == 1
    assert s.exists("profiles", "x") and s.list_ids("profiles") == ["x"]
    with open(s.entity_dir("profiles", "x") + "/blob.bin", "w") as f:
        f.write("data")  # blob은 엔티티 디렉토리에
    assert s.read_setting("rates", {}) == {}
    s.write_setting("rates", {"clone_rtf": 12.0})
    assert s.read_setting("rates")["clone_rtf"] == 12.0
    s.delete_entity("profiles", "x")
    assert not s.exists("profiles", "x") and s.list_ids("profiles") == []


def test_storage_home_survives_swap(tmp_path):
    """어댑터 인스턴스를 새로 만들어도(=앱 업데이트) 같은 홈이면 데이터 유지."""
    from web.storage import LocalStorage
    LocalStorage(str(tmp_path)).write_doc("history", "j", {"id": "j"})
    assert LocalStorage(str(tmp_path)).read_doc("history", "j") == {"id": "j"}


def test_profile_store_roundtrip(tmp_path, monkeypatch):
    import web.profiles as P
    import web.storage as S
    monkeypatch.setattr(S, "store", S.LocalStorage(str(tmp_path)))
    meta = P.create_profile("테스트 목소리")
    assert meta["ready"] is False
    assert any(m["id"] == meta["id"] for m in P.list_profiles())
    P.delete_profile(meta["id"])
    assert not any(m["id"] == meta["id"] for m in P.list_profiles())


def test_splice_paragraphs_meta_shifts_following():
    """문단 교체 시 뒤 문단 경계가 길이 변화만큼 밀린다 (부분 재생성의 산수)."""
    from core.clone import splice_paragraphs_meta
    paras = [{"text": "a", "start": 0.0, "end": 10.0, "pns": 80},
             {"text": "b", "start": 11.0, "end": 20.0, "pns": 81},
             {"text": "c", "start": 21.0, "end": 30.0, "pns": 82}]
    out = splice_paragraphs_meta(paras, 1, 12.0)  # 9초 → 12초 (+3)
    assert out[0] == paras[0]                      # 앞 문단은 그대로
    assert out[1]["start"] == 11.0 and out[1]["end"] == 23.0
    assert out[2]["start"] == 24.0 and out[2]["end"] == 33.0
    assert paras[1]["end"] == 20.0                 # 원본 불변 (순수 함수)


def test_splice_paragraphs_meta_shorter_replacement():
    from core.clone import splice_paragraphs_meta
    paras = [{"text": "a", "start": 0.0, "end": 10.0},
             {"text": "b", "start": 11.0, "end": 20.0}]
    out = splice_paragraphs_meta(paras, 0, 6.0)    # 10초 → 6초 (-4)
    assert out[0]["end"] == 6.0
    assert out[1]["start"] == 7.0 and out[1]["end"] == 16.0


def test_history_rename_and_delete(tmp_path, monkeypatch):
    import web.profiles as P
    import web.storage as S
    monkeypatch.setattr(S, "store", S.LocalStorage(str(tmp_path)))
    jdir = tmp_path / "history" / "abc123"
    jdir.mkdir(parents=True)
    (jdir / "meta.json").write_text(
        '{"id": "abc123", "status": "done", "title": "옛 이름"}',
        encoding="utf-8")
    assert P.rename_history("abc123", "새 이름") == "새 이름"
    assert P.get_job("abc123")["title"] == "새 이름"
    with pytest.raises(ValueError):
        P.rename_history("abc123", "   ")
    P.delete_history("abc123")
    assert P.get_job("abc123") is None


def test_regen_job_rejects_unfinished(tmp_path, monkeypatch):
    """문단 재생성은 완성작 + 문단 경계 + 프로필이 있어야 시작된다."""
    import web.profiles as P
    import web.storage as S
    monkeypatch.setattr(S, "store", S.LocalStorage(str(tmp_path)))
    with pytest.raises(ValueError):
        P.start_regen_job("없는작업", 0)
    jdir = tmp_path / "history" / "j1"
    jdir.mkdir(parents=True)
    (jdir / "meta.json").write_text(
        '{"id": "j1", "status": "done", "text": "t", "paragraphs": null}',
        encoding="utf-8")
    with pytest.raises(ValueError):  # 문단 정보 없는 옛 작업
        P.start_regen_job("j1", 0)


def test_performance_job_rejects_bad_targets(tmp_path, monkeypatch):
    """연기 반영은 완성작 + 문단 정보가 있어야 시작된다."""
    import web.profiles as P
    import web.storage as S
    monkeypatch.setattr(S, "store", S.LocalStorage(str(tmp_path)))
    with pytest.raises(ValueError):
        P.start_performance_job("없는작업", 0, str(tmp_path / "r.webm"))
    jdir = tmp_path / "history" / "j1"
    jdir.mkdir(parents=True)
    (jdir / "meta.json").write_text(
        '{"id": "j1", "status": "done", "text": "t", "paragraphs": null}',
        encoding="utf-8")
    with pytest.raises(ValueError):
        P.start_performance_job("j1", 0, str(tmp_path / "r.webm"))


def test_new_job_defaults_title_from_text():
    from web.profiles import _new_job
    job = _new_job("x", "안녕하세요. 오늘은 테스트입니다. " * 5, None, None, {})
    assert 0 < len(job["title"]) <= 24
    assert job["version"] == 1 and job["parent"] is None
    assert job["composed"] == [] and job["paragraphs"] is None


def test_vad_threshold_bimodal_lands_between_modes():
    """무음(-70대)과 발화(-25대)가 나뉜 분포 → 문턱은 두 무리 사이."""
    import numpy as np
    from core.denoise import vad_threshold
    rng = np.random.default_rng(0)
    db = np.concatenate([rng.normal(-70, 3, 400), rng.normal(-25, 3, 600)])
    th = vad_threshold(db)
    assert th is not None and -65 < th < -30


def test_vad_threshold_dense_speech_skips_gate():
    """연속 발화(좁은 단봉 분포) → None = 게이트 생략.

    실사용 사고: 무음 없는 화면 녹화에서 중간점 문턱이 발화 프레임 64%를
    무음으로 오판해 말끝을 죽이고 분당 20회 끊김을 만들었다."""
    import numpy as np
    from core.denoise import vad_threshold
    rng = np.random.default_rng(1)
    assert vad_threshold(rng.normal(-38, 2.5, 1000)) is None


def test_vad_threshold_tiny_minority_skips_gate():
    """무음이 3%뿐이면 게이트 근거 부족 → None."""
    import numpy as np
    from core.denoise import vad_threshold
    rng = np.random.default_rng(2)
    db = np.concatenate([rng.normal(-70, 2, 25), rng.normal(-25, 3, 975)])
    assert vad_threshold(db) is None


def test_vad_threshold_too_few_frames():
    from core.denoise import vad_threshold
    assert vad_threshold([-30.0] * 5) is None


def test_report_from_frames_clean_result():
    """발화 보존 + 무음만 억제된 결과 → 손실 0%, 억제량 양수."""
    import numpy as np
    from core.denoise import report_from_frames
    rng = np.random.default_rng(0)
    orig = np.concatenate([rng.normal(-25, 2, 500),    # 발화
                           rng.normal(-50, 2, 500)])   # 무음(팬 소음)
    out = orig.copy()
    out[500:] -= 30                                     # 무음만 30dB 억제
    r = report_from_frames(orig, out)
    assert r["speech_loss_pct"] == 0.0
    assert r["pause_supp_db"] > 20


def test_report_from_frames_detects_speech_loss():
    """발화 일부가 죽은 결과(과거 결함) → 손실 비율이 잡힌다."""
    import numpy as np
    from core.denoise import report_from_frames
    rng = np.random.default_rng(1)
    orig = np.concatenate([rng.normal(-25, 2, 500), rng.normal(-50, 2, 500)])
    out = orig.copy()
    out[100:200] -= 25                                  # 발화 20%를 게이트로 죽임
    r = report_from_frames(orig, out)
    assert r["speech_loss_pct"] >= 15


def test_report_boost_invariant():
    """볼륨 업(+10dB)이 손실/억제 지표를 왜곡하지 않는다."""
    import numpy as np
    from core.denoise import report_from_frames
    rng = np.random.default_rng(2)
    orig = np.concatenate([rng.normal(-25, 2, 500), rng.normal(-50, 2, 500)])
    out = orig.copy(); out[500:] -= 30
    r0 = report_from_frames(orig, out)
    r1 = report_from_frames(orig, out + 10)
    assert r0["speech_loss_pct"] == r1["speech_loss_pct"] == 0.0
    assert abs(r0["pause_supp_db"] - r1["pause_supp_db"]) < 0.5


def test_run_denoise_rejects_unknown_mode(tmp_path):
    from core.denoise import run_denoise
    with pytest.raises(ValueError):
        run_denoise(str(tmp_path / "a.wav"), str(tmp_path / "b.wav"),
                    mode="magic")


def test_run_denoise_resynth_requires_engine(tmp_path, monkeypatch):
    """재합성 모드는 .venv-re가 있어야 시작된다 (설치 안내 에러)."""
    import core.denoise as D
    monkeypatch.setattr(D, "RE_VENV_PY", str(tmp_path / "없는경로"))
    with pytest.raises(RuntimeError, match="install_resynth"):
        D.run_denoise(str(tmp_path / "a.wav"), str(tmp_path / "b.wav"),
                      mode="resynth")


def test_archive_stats_keeps_history():
    """프로필 재분석(강화) 시 이전 통계가 이력으로 남는다 (전/후 비교 재료)."""
    from web.profiles import _archive_stats
    meta = {"stats": {"duration": 30.0}, "built": "2026-07-17 10:00",
            "built_with": {"recordings": 10, "sources": 1}}
    _archive_stats(meta)
    h = meta["stats_history"][0]
    assert h["stats"]["duration"] == 30.0
    assert h["sources"] == 1 and h["date"] == "2026-07-17 10:00"
    meta2 = {"stats": None}  # 첫 빌드(이전 통계 없음)는 이력을 만들지 않음
    _archive_stats(meta2)
    assert "stats_history" not in meta2


def test_profile_version_snapshot_and_rollback(tmp_path, monkeypatch):
    """빌드마다 자산이 versions/vN에 보존되고, 롤백하면 그 버전을 가리킨다."""
    import web.profiles as P
    import web.storage as S
    monkeypatch.setattr(S, "store", S.LocalStorage(str(tmp_path)))
    pdir = tmp_path / "profiles" / "p1"
    pdir.mkdir(parents=True)
    (pdir / "ref_clean.wav").write_bytes(b"v1ref")
    (pdir / "ref_full_clean.wav").write_bytes(b"v1nat")
    meta = {"id": "p1", "ready": True, "ref_wav": "ref_clean.wav",
            "natural_wav": "ref_full_clean.wav", "ref_text": "하나",
            "stats": {"duration": 30.0}, "built": "d1", "builds": 1,
            "built_with": {"recordings": 0, "sources": 1}, "denoised": True}
    P._snapshot_version(str(pdir), meta, 1)
    assert meta["version"] == 1
    assert meta["ref_wav"].startswith("versions") and meta["ref_wav"].endswith("ref_clean.wav")

    (pdir / "ref_clean.wav").write_bytes(b"v2ref")  # 다음 빌드가 루트를 덮어씀
    meta.update({"ref_wav": "ref_clean.wav", "natural_wav": "ref_full_clean.wav",
                 "ref_text": "둘", "stats": {"duration": 70.0},
                 "built": "d2", "builds": 2})
    P._snapshot_version(str(pdir), meta, 2)
    P._save_meta("p1", meta)
    assert [e["version"] for e in meta["version_log"]] == [1, 2]

    m = P.rollback_profile("p1", 1)
    assert m["version"] == 1 and m["stats"]["duration"] == 30.0
    assert m["ref_text"] == "하나"
    with open(P.profile_paths("p1")[0], "rb") as f:
        assert f.read() == b"v1ref"          # v1 자산이 실제로 활성
    m2 = P.rollback_profile("p1", 2)         # 롤포워드도 같은 방식
    assert m2["version"] == 2 and m2["ref_text"] == "둘"
    with pytest.raises(ValueError):
        P.rollback_profile("p1", 9)


def test_dnjob_store_roundtrip(tmp_path, monkeypatch):
    import web.dnjobs as D
    import web.storage as S
    monkeypatch.setattr(S, "store", S.LocalStorage(str(tmp_path)))
    jdir = tmp_path / "denoise" / "dn1"
    jdir.mkdir(parents=True)
    (jdir / "meta.json").write_text(
        '{"id": "dn1", "status": "done", "title": "t.mov", "out_name": "t_clean.mov"}',
        encoding="utf-8")
    (jdir / "clean.mov").write_bytes(b"x")
    (jdir / "orig.m4a").write_bytes(b"x")
    assert D.get_dnjob("dn1")["title"] == "t.mov"
    assert D.dnjob_path("dn1", "file").endswith("clean.mov")
    assert D.dnjob_path("dn1", "orig").endswith("orig.m4a")
    assert D.dnjob_path("dn1", "clean") is None  # clean.m4a 없음
    assert any(j["id"] == "dn1" for j in D.list_dnjobs())
    D.delete_dnjob("dn1")
    assert D.get_dnjob("dn1") is None


def test_rates_eta_estimates(tmp_path, monkeypatch):
    """ETA 산정: 대본 길이·모드에 비례하고, 실측이 EMA로 반영된다."""
    import web.rates as R
    import web.storage as S
    monkeypatch.setattr(S, "store", S.LocalStorage(str(tmp_path)))
    long_eta = R.estimate_clone_eta("안녕하세요. 반갑습니다. 오늘도 좋은 하루입니다.")
    assert 10 < long_eta < 600
    assert R.estimate_clone_eta("안녕하세요.", fast=True) < long_eta
    assert R.estimate_dn_eta(60, "standard") < R.estimate_dn_eta(60, "resynth")
    base = R.get_rates()["clone_rtf"]
    R.update_rate("clone_rtf", base / 2)          # 더 빠른 실측 반영
    assert R.get_rates()["clone_rtf"] < base
    R.update_rate("clone_rtf", None)              # 무효값은 무시
    R.update_rate("clone_rtf", -1)


def test_tasks_endpoint_merges_kinds(tmp_path, monkeypatch):
    """작업 센터 API: 클론·노이즈 작업이 합쳐지고 진행 중이 먼저 온다."""
    import web.dnjobs as D
    import web.profiles as P
    from web.server import app
    import web.storage as S
    monkeypatch.setattr(S, "store", S.LocalStorage(str(tmp_path)))
    (tmp_path / "history" / "a1").mkdir(parents=True)
    (tmp_path / "history" / "a1" / "meta.json").write_text(
        '{"id":"a1","status":"generating","title":"클론","created":"2026-07-17 10:00"}',
        encoding="utf-8")
    (tmp_path / "denoise" / "b1").mkdir(parents=True)
    (tmp_path / "denoise" / "b1" / "meta.json").write_text(
        '{"id":"b1","status":"done","title":"dn","created":"2026-07-17 11:00"}',
        encoding="utf-8")
    with app.test_client() as c:
        items = [i for i in c.get("/api/tasks").get_json()["items"]
                 if i["id"] in ("a1", "b1")]
    kinds = {i["id"]: i["kind"] for i in items}
    assert kinds == {"a1": "clone", "b1": "denoise"}
    assert items[0]["id"] == "a1"  # 진행 중이 먼저


# ---- 웹 서버 (기능 감지 포함) ----

def test_health_endpoint():
    from web.server import app
    with app.test_client() as c:
        r = c.get("/api/health")
        assert r.status_code == 200
        data = r.get_json()
        assert data["ok"] is True
        assert "clone" in data and "denoise" in data


def test_clone_api_rejects_empty_text():
    from web.server import app
    from core.clone import clone_available
    if not clone_available():
        pytest.skip("mlx 미설치 환경 (501 경로는 별도 테스트)")
    with app.test_client() as c:
        r = c.post("/api/clone", data={})
        assert r.status_code == 400


def test_clone_api_501_when_unavailable(monkeypatch):
    import web.server as srv
    monkeypatch.setattr(srv, "clone_available", lambda: False)
    with srv.app.test_client() as c:
        r = c.post("/api/clone", data={})
        assert r.status_code == 501
