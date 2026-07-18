# 저장소 어댑터 (업데이트 내구성 · 클라우드 전환)

사용자 데이터(보이스 프로필·작업 기록·설정)의 모든 영속 접근은 단일 어댑터
`web/storage.py`의 `store`를 경유한다. 목표 두 가지:

## 1. 앱 업데이트에도 데이터 유지 — 검증됨

데이터는 **앱 번들 밖**의 사용자 홈에 산다:

```
~/.noisecleaner/            (NOISECLEANER_HOME 으로 변경 가능)
├─ profiles/<id>/meta.json + raw/ sources/ versions/ ...
├─ history/<id>/meta.json + output.wav
├─ denoise/<id>/meta.json + clean.* orig.m4a clean.m4a
└─ rates.json               (ETA 학습 설정)
```

앱 번들(`dist/NoiseCleaner/` 또는 개발 리포)을 새 버전으로 통째로 교체해도
이 홈은 건드리지 않으므로 프로필·작업이 그대로 남는다.

**실측:** 기존 홈을 그대로 둔 채 어댑터로 전면 교체 후, 기존 프로필 4·히스토리
20·작업센터 25건이 투명하게 로드됨(온디스크 레이아웃 동일 → 마이그레이션
불필요). 어댑터 인스턴스를 새로 만들어도 같은 홈이면 데이터 유지 확인.

## 2. 클라우드 전환 seam

`Storage`(ABC)를 구현한 백엔드를 갈아 끼우면 되고, 앱 코드
(profiles·dnjobs·rates)는 그대로다. 세 가지 추상:

| 추상 | 로컬 | 클라우드(예시) |
|---|---|---|
| **문서**(meta.json) | 파일 | 문서 DB(Firestore/Dynamo) |
| **엔티티 디렉토리**(blob) | 실제 폴더 | 로컬 캐시 + S3/GCS 동기화 |
| **설정**(rates) | 루트 JSON | KV |

인터페이스: `read_doc`/`write_doc`/`exists`/`list_ids`/`delete_entity`,
`entity_dir`(blob 위치), `read_setting`/`write_setting`,
그리고 클라우드 동기화 훅 `commit(kind,eid)`(쓰기 후 업로드)·
`ensure_local(kind,eid)`(읽기 전 다운로드) — 로컬은 no-op.

### 클라우드 백엔드 추가법

1. `web/storage.py`에 `class CloudStorage(Storage)` 구현
   (문서는 DB, blob은 `entity_dir`를 로컬 캐시로 두고 commit/ensure_local로
   S3 동기화).
2. `_make_backend()`에 `NOISECLEANER_STORAGE=s3` 분기 등록.
3. 끝. 앱 코드 수정 없음.

backend 선택: 환경변수 `NOISECLEANER_STORAGE`(기본 `local`).

### 현재 상태

- ✅ `LocalStorage` 구현·검증 (단위 테스트 + 라이브 쓰기/읽기/삭제 주기)
- ⏳ 클라우드 백엔드는 seam만 준비. 실제 구현은 필요 시.
  (blob 동기화 시 대용량 오디오 업/다운로드 비용·오프라인 캐시 정책이
  설계 포인트 — commit/ensure_local 훅이 그 자리다.)
