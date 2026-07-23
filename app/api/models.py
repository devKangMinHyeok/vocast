"""온디바이스 모델 관리 — 앱 첫 실행 시 다운로드.

TTS(Qwen3-TTS)·전사(whisper) 모델은 용량이 커서 앱에 번들하지 않고 첫 실행 때
내려받는다(디자인: "최초 모델 다운로드 후 오프라인"). 노이즈 제거 모델은 이미
voxa/models에 번들되어 오프라인으로 바로 동작한다.

저장 위치는 HF_HOME이 가리키는 곳(맥 앱은 앱 소유 폴더로 지정 → 앱 바운더리에 격리).
리비전을 고정해 재현 가능하게 받는다. 진행률은 디스크 용량으로 실측한다.
"""
import contextlib
import os
import threading

import huggingface_hub
from huggingface_hub import snapshot_download


@contextlib.contextmanager
def _online():
    """이 블록 동안만 HuggingFace 허브 접속을 허용한다.

    엔진은 기본적으로 오프라인(HF_HUB_OFFLINE=1)으로 뜬다 — 캐시된 모델이
    있는데도 허브에 리비전을 확인하러 나갔다가 오프라인 상태에서 무한 대기하는
    사고를 막기 위해서다(렌더가 'reference' 단계에서 멈추던 원인). 모델
    다운로드만은 네트워크가 필요하므로 그 구간에서만 오프라인을 잠시 해제한다.
    huggingface_hub은 HF_HUB_OFFLINE을 import 시점에 constants로 굳히므로,
    런타임 토글은 그 constants 값을 직접 바꿔야 반영된다(env는 함께 맞춰둔다).
    """
    prev_env = os.environ.get("HF_HUB_OFFLINE")
    prev_const = huggingface_hub.constants.HF_HUB_OFFLINE
    os.environ["HF_HUB_OFFLINE"] = "0"
    huggingface_hub.constants.HF_HUB_OFFLINE = False
    try:
        yield
    finally:
        huggingface_hub.constants.HF_HUB_OFFLINE = prev_const
        if prev_env is None:
            os.environ.pop("HF_HUB_OFFLINE", None)
        else:
            os.environ["HF_HUB_OFFLINE"] = prev_env

# key -> (repo_id, pinned_revision, approx_size_mb)
MODELS = {
    "tts_fast": ("mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit",
                 "50f45ef0047cde7e84c2ef04326acb8ada2436a7", 1900),
    "tts_best": ("mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit",
                 "e7dd0585652209fa0d7783659aad4e8a324de11c", 2900),
    "whisper":  ("mlx-community/whisper-large-v3-turbo",
                 "a4aaeec0636e6fef84abdcbe3544cb2bf7e9f6fb", 1500),
}

# 다운로드 묶음: balanced = 빠른 TTS + 전사, advanced = 고품질 TTS 추가
TIERS = {
    "balanced": ["tts_fast", "whisper"],
    "advanced": ["tts_fast", "whisper", "tts_best"],
}

_LOCK = threading.Lock()
_STATE = {"downloading": False, "tier": "balanced", "current": None,
          "done": False, "error": None}


def _hub_root() -> str:
    home = os.environ.get("HF_HOME") or os.path.expanduser("~/.cache/huggingface")
    return os.path.join(home, "hub")


def _model_dir(repo_id: str) -> str:
    return os.path.join(_hub_root(), "models--" + repo_id.replace("/", "--"))


def _dir_mb(path: str) -> int:
    total = 0
    for root, _dirs, files in os.walk(path):
        for f in files:
            try:
                total += os.path.getsize(os.path.join(root, f))
            except OSError:
                pass
    return total // (1024 * 1024)


def is_installed(key: str) -> bool:
    repo, rev, _ = MODELS[key]
    snap = os.path.join(_model_dir(repo), "snapshots", rev)
    return os.path.isdir(snap) and bool(os.listdir(snap))


def installed_map() -> dict:
    return {k: is_installed(k) for k in MODELS}


def start_download(tier: str) -> bool:
    """백그라운드 다운로드 시작. 이미 진행 중이면 False."""
    keys = TIERS.get(tier, TIERS["balanced"])
    with _LOCK:
        if _STATE["downloading"]:
            return False
        _STATE.update(downloading=True, tier=tier, current=None,
                      done=False, error=None)

    def run():
        try:
            for k in keys:
                repo, rev, _ = MODELS[k]
                _STATE["current"] = k
                # 이미 완전히 받아져 있으면 즉시 반환, 부분이면 이어받아 완성.
                # 다운로드 구간에서만 오프라인 해제(엔진 기본은 오프라인).
                with _online():
                    snapshot_download(repo, revision=rev)  # HF_HOME 아래로 격리 저장
            _STATE["done"] = True
        except Exception as e:  # noqa: BLE001
            _STATE["error"] = str(e)[-300:]
        finally:
            _STATE["downloading"] = False

    threading.Thread(target=run, daemon=True).start()
    return True


def status() -> dict:
    tier = _STATE["tier"] or "balanced"
    keys = TIERS.get(tier, TIERS["balanced"])
    total = got = 0
    for k in keys:
        _repo, _rev, size = MODELS[k]
        total += size
        got += min(_dir_mb(_model_dir(MODELS[k][0])), size)
    # 다운로드 중에는 snapshot 디렉터리가 조기 생성될 수 있으므로, 완료 판정은
    # "진행 중이 아니고 모든 모델이 설치됨"으로 한다.
    ready = (not _STATE["downloading"]) and all(is_installed(k) for k in keys)
    return {
        "tier": tier,
        "downloading": _STATE["downloading"],
        "current": _STATE["current"],
        "done": ready,
        "ready": ready,
        "error": _STATE["error"],
        "downloaded_mb": got,
        "total_mb": total,
        "installed": installed_map(),
        "store": _hub_root(),
    }
