"""ETA 콜드 스타트 회귀 테스트.

엔진이 새로 뜨고 첫 클론은 TTS 모델 로드(수십 초)를 포함하는데, RTF 기반 추정엔
그 1회성 비용이 없어 과소추정됐다. 이제 모델이 아직 warm이 아니면 cold_start를
더하고, 콜드 실행의 소요시간이 warm RTF를 오염시키지 않게 분리 학습한다.
"""

from api import rates, storage


def _isolate(tmp):
    storage.configure(home=str(tmp))
    rates._WARM.clear()   # 프로세스 warm 상태 초기화


def test_cold_estimate_is_larger_than_warm(tmp_path):
    _isolate(tmp_path)
    text = "안녕하세요 " * 20
    warm = rates.estimate_clone_eta(text, warm=True)
    cold = rates.estimate_clone_eta(text, warm=False)
    assert cold - warm == round(rates.get_rates()["cold_start"])


def test_warmth_tracking(tmp_path):
    _isolate(tmp_path)
    assert not rates.is_warm(fast=False)
    rates.mark_warm(fast=False)
    assert rates.is_warm(fast=False)
    # fast/best are tracked independently
    assert not rates.is_warm(fast=True)


def test_default_is_warm(tmp_path):
    # Callers that don't care (regen) get a warm estimate by default.
    _isolate(tmp_path)
    text = "테스트 문장입니다 " * 5
    assert rates.estimate_clone_eta(text) == rates.estimate_clone_eta(text, warm=True)


def test_english_text_falls_back_to_char_estimate(tmp_path):
    _isolate(tmp_path)
    # No Hangul: uses a char-based syllable estimate rather than zero.
    eta = rates.estimate_clone_eta("This is an English script.", warm=True)
    assert eta > round(rates.get_rates()["align_overhead"])


# --- 세션 중 멈춘 작업 감지 워치독 (reconcile_stale) ---
import os
import time as _time


def _age_doc(kind, jid, seconds):
    """작업 문서 meta.json의 mtime을 seconds초 과거로 돌린다 (하트비트 정지 모사)."""
    path = os.path.join(storage.store.entity_dir(kind, jid, ensure=False), "meta.json")
    past = _time.time() - seconds
    os.utime(path, (past, past))


def test_stale_watchdog_marks_silent_job(tmp_path):
    from api import profiles
    storage.configure(home=str(tmp_path))
    storage.store.write_doc("history", "silent", {
        "id": "silent", "kind": "clone", "status": "generating", "stage": "takes"})
    _age_doc("history", "silent", 700)  # 700s 무진행 (> 600 임계)
    assert profiles.reconcile_stale(silence=600) == 1
    assert storage.store.read_doc("history", "silent")["status"] == "error"
    assert "stuck" in storage.store.read_doc("history", "silent")["error"]


def test_stale_watchdog_leaves_progressing_job(tmp_path):
    from api import profiles
    storage.configure(home=str(tmp_path))
    # 방금 써진(진행 중인) 작업은 하트비트가 최신이라 건드리지 않는다.
    storage.store.write_doc("history", "live", {
        "id": "live", "kind": "clone", "status": "generating", "stage": "take 2/3"})
    assert profiles.reconcile_stale(silence=600) == 0
    assert storage.store.read_doc("history", "live")["status"] == "generating"


def test_stale_watchdog_ignores_terminal_job(tmp_path):
    from api import profiles
    storage.configure(home=str(tmp_path))
    storage.store.write_doc("history", "done1", {
        "id": "done1", "kind": "clone", "status": "done", "stage": "done"})
    _age_doc("history", "done1", 999999)  # 아주 오래됐어도 종료 상태라 무시
    assert profiles.reconcile_stale(silence=600) == 0
    assert storage.store.read_doc("history", "done1")["status"] == "done"
