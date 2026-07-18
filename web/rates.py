"""작업 예상 시간(ETA) 산정 — 실측 이력 기반. 앱 계층.

"2초 이상 걸리는 모든 프로세스는 예상 완료 시간을 보여준다" 원칙의 데이터원.
작업이 끝날 때마다 실측 속도를 지수이동평균(EMA)으로 반영하므로,
쓸수록 이 기기·이 설정에 맞게 정확해진다.

저장: 저장소 어댑터의 설정(setting) "rates" — web/storage.py 참고.
"""
import re

from web import storage

# 초기값은 이 프로젝트의 실측에서 가져온 보수적 추정
DEFAULTS = {
    "clone_rtf": 16.0,       # 클론 생성: 출력 1초당 처리 초 (실측 13~21)
    "clone_fast_rtf": 5.0,   # 빠른 모드(1테이크)
    "dn_standard": 0.35,     # 표준 노이즈 제거: 입력 1초당 (실측 0.27)
    "dn_resynth": 3.6,       # 재합성: 입력 1초당 (실측 3.2 + 리포트)
    "build_factor": 0.7,     # 프로필 분석: 학습 음성 1초당 (실측 ~0.5)
    "align_overhead": 8.0,   # 완료 후 가사 정렬 등 고정 오버헤드(초)
}


def get_rates():
    return {**DEFAULTS, **(storage.store.read_setting("rates", {}) or {})}


def update_rate(key, value, alpha=0.4):
    """실측값을 EMA로 반영 (α=0.4 — 최근 실행에 빠르게 적응)."""
    if value is None or value <= 0:
        return
    rates = get_rates()
    rates[key] = round((1 - alpha) * rates.get(key, value) + alpha * value, 3)
    storage.store.write_setting("rates", rates)


def estimate_clone_eta(text, fast=False, speech_rate=None):
    """대본 → 예상 처리 초. 음절 수 ÷ 말 속도 = 예상 오디오 길이 × RTF."""
    syllables = len(re.findall(r"[가-힣]", text)) or max(len(text) // 3, 1)
    audio_sec = syllables / (speech_rate or 6.5) * 1.2  # 호흡 여유 20%
    r = get_rates()
    rtf = r["clone_fast_rtf"] if fast else r["clone_rtf"]
    return round(audio_sec * rtf + r["align_overhead"])


def estimate_dn_eta(duration_sec, mode="standard"):
    """미디어 길이 → 노이즈 제거 예상 초 (모드별 실측 배율)."""
    r = get_rates()
    per = r["dn_resynth"] if mode == "resynth" else r["dn_standard"]
    return round((duration_sec or 60) * per + 10)


def estimate_build_eta(total_audio_sec):
    """학습 음성 총 길이 → 프로필 분석 예상 초."""
    r = get_rates()
    return round(max(total_audio_sec, 10) * r["build_factor"] + 20)
