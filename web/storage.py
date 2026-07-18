"""저장소 어댑터 계층 — 앱 계층.

목표 두 가지:
1. **업데이트 내구성**: 사용자 데이터(프로필·작업 기록)는 앱 번들 밖의
   사용자 홈(`~/.noisecleaner`, `NOISECLEANER_HOME`으로 변경 가능)에 산다.
   앱을 새 버전으로 교체해도 이 폴더는 그대로 남아 데이터가 유지된다.
2. **클라우드 전환 seam**: 모든 영속 접근을 이 인터페이스 하나로 모은다.
   나중에 `Storage`를 구현한 `CloudStorage`(S3/GCS + 문서 DB)로 바꿔 끼우면
   되며, 앱 코드(profiles·dnjobs·rates)는 그대로다.

세 가지 추상:
- **문서(document)**: 엔티티의 meta.json (프로필/작업의 구조화 상태). JSON.
- **엔티티 디렉토리(entity dir)**: blob(오디오·영상·버전 스냅샷)이 사는 곳.
  로컬은 실제 폴더. 클라우드는 로컬 캐시 폴더 + commit/ensure_local로 동기화.
- **설정(setting)**: 루트의 단일 JSON (예: rates.json).

클라우드 확장점: `commit(kind, eid)`(쓰기 후 업로드), `ensure_local(kind, eid)`
(읽기 전 다운로드). 로컬 구현에선 no-op이라 동작·성능에 영향이 없다.

backend 선택: 환경변수 `NOISECLEANER_STORAGE`(기본 "local"). 미래에
"s3"·"gcs" 등을 추가한다.
"""
import json
import os
import shutil
from abc import ABC, abstractmethod

# kind → 홈 하위 디렉토리(=문서 컬렉션). 새 컬렉션은 여기만 추가.
KINDS = {"profiles": "profiles", "history": "history", "denoise": "denoise"}


class Storage(ABC):
    """영속 저장소 인터페이스. 로컬·클라우드가 이걸 구현한다."""

    # --- 위치 ---
    @abstractmethod
    def home(self) -> str: ...

    @abstractmethod
    def entity_dir(self, kind: str, eid: str, ensure: bool = True) -> str:
        """엔티티(프로필/작업)의 blob 디렉토리 경로. 처리 파이프라인이 이 안에
        파일을 쓴다. 클라우드에선 로컬 캐시 경로를 돌려주고 commit으로 올린다."""

    # --- 문서(meta.json) ---
    @abstractmethod
    def read_doc(self, kind: str, eid: str) -> dict | None: ...
    @abstractmethod
    def write_doc(self, kind: str, eid: str, obj: dict) -> None: ...
    @abstractmethod
    def exists(self, kind: str, eid: str) -> bool: ...
    @abstractmethod
    def list_ids(self, kind: str) -> list: ...
    @abstractmethod
    def delete_entity(self, kind: str, eid: str) -> None: ...

    # --- 엔티티 내부 임의 JSON (버전 스냅샷 등) ---
    @abstractmethod
    def read_json(self, path: str) -> dict | None: ...
    @abstractmethod
    def write_json(self, path: str, obj: dict) -> None: ...

    # --- 설정(단일 파일) ---
    @abstractmethod
    def read_setting(self, name: str, default=None): ...
    @abstractmethod
    def write_setting(self, name: str, obj) -> None: ...

    # --- 클라우드 동기화 훅 (로컬은 no-op) ---
    def commit(self, kind: str, eid: str) -> None:
        """엔티티의 문서+blob을 영속화(클라우드 업로드). 로컬은 이미 디스크."""

    def ensure_local(self, kind: str, eid: str) -> None:
        """엔티티 blob을 로컬에서 읽을 수 있게 보장(클라우드 다운로드)."""


class LocalStorage(Storage):
    """파일시스템 구현 — 사용자 홈의 폴더 트리. 현재 동작을 그대로 재현."""

    def __init__(self, home: str):
        self._home = home

    def home(self) -> str:
        return self._home

    def _kind_root(self, kind: str) -> str:
        d = os.path.join(self._home, KINDS[kind])
        os.makedirs(d, exist_ok=True)
        return d

    def entity_dir(self, kind, eid, ensure=True) -> str:
        d = os.path.join(self._home, KINDS[kind], eid)
        if ensure:
            os.makedirs(d, exist_ok=True)
        return d

    def _meta_path(self, kind, eid) -> str:
        return os.path.join(self._home, KINDS[kind], eid, "meta.json")

    def read_doc(self, kind, eid):
        return self.read_json(self._meta_path(kind, eid))

    def write_doc(self, kind, eid, obj):
        self.entity_dir(kind, eid)  # 디렉토리 보장
        self.write_json(self._meta_path(kind, eid), obj)

    def exists(self, kind, eid) -> bool:
        return os.path.exists(self._meta_path(kind, eid))

    def list_ids(self, kind):
        root = self._kind_root(kind)
        return sorted(e for e in os.listdir(root)
                      if os.path.isdir(os.path.join(root, e)))

    def delete_entity(self, kind, eid):
        shutil.rmtree(self.entity_dir(kind, eid, ensure=False),
                      ignore_errors=True)

    def read_json(self, path):
        try:
            with open(path, encoding="utf-8") as f:
                return json.load(f)
        except (OSError, json.JSONDecodeError):
            return None

    def write_json(self, path, obj):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False, indent=2)

    def _setting_path(self, name) -> str:
        return os.path.join(self._home, f"{name}.json")

    def read_setting(self, name, default=None):
        v = self.read_json(self._setting_path(name))
        return v if v is not None else default

    def write_setting(self, name, obj):
        os.makedirs(self._home, exist_ok=True)
        self.write_json(self._setting_path(name), obj)


def _default_home() -> str:
    return os.environ.get("NOISECLEANER_HOME",
                          os.path.expanduser("~/.noisecleaner"))


def _make_backend() -> Storage:
    backend = os.environ.get("NOISECLEANER_STORAGE", "local")
    if backend == "local":
        return LocalStorage(_default_home())
    raise RuntimeError(
        f"알 수 없는 저장소 백엔드: {backend} (현재 'local'만 지원). "
        "클라우드 백엔드는 Storage를 구현해 여기에 등록하세요.")


# 모듈 싱글턴 — 앱 코드는 이걸 통해서만 영속 접근한다.
store: Storage = _make_backend()


def configure(home: str = None, backend: Storage = None) -> Storage:
    """저장소 재설정 (테스트·전환용). backend 직접 주입 또는 로컬 home 지정."""
    global store
    store = backend if backend is not None else LocalStorage(
        home or _default_home())
    return store
