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


def test_profile_store_roundtrip(tmp_path, monkeypatch):
    import web.profiles as P
    monkeypatch.setattr(P, "PROFILES_DIR", str(tmp_path / "profiles"))
    monkeypatch.setattr(P, "HISTORY_DIR", str(tmp_path / "history"))
    meta = P.create_profile("테스트 목소리")
    assert meta["ready"] is False
    assert any(m["id"] == meta["id"] for m in P.list_profiles())
    P.delete_profile(meta["id"])
    assert not any(m["id"] == meta["id"] for m in P.list_profiles())


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
