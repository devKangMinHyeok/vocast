# 이식성 · 환경 격리

이 앱은 **개발자 기기의 시스템 상태에 의존하지 않도록** 봉인되어 있다.
"내 Mac에서만 되는" 상태를 없애고, 판매 배포와 재현을 위한 기반을 만든다.

## 유일한 전제: uv

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
bash bootstrap.sh
```

uv는 단일 정적 바이너리(수 MB)다. brew·시스템 파이썬·ffmpeg 설치가 전부 불필요.

## 무엇이 봉인되는가

| 이전 (시스템 의존) | 지금 (봉인) |
|---|---|
| `brew install python@3.11` | uv가 **관리형 CPython 3.11/3.12**를 내려받음 |
| `brew install ffmpeg` (+ffprobe) | **imageio-ffmpeg 휠**로 ffmpeg 7.1 동봉 (arnndn·aac 포함 확인). ffprobe는 안 씀 — `ffmpeg -i` stderr 파싱으로 대체 |
| `pip install`로 그때그때 버전 | **uv.lock**으로 전 버전 고정, 클린룸 재현 검증됨 |
| 세 venv가 절대경로로 서로 참조 | 상대경로(`ROOT` 기준), 폴더째 이동 가능 |

## 세 개의 격리된 환경

의존성 충돌(구버전 torch·deepspeed) 때문에 엔진마다 전용 venv를 쓴다.
전부 uv 관리 파이썬으로 만들어진다.

| 환경 | 파이썬 | 용도 | 설치 |
|---|---|---|---|
| `.venv` | 3.12 | 웹 앱·클로닝·오케스트레이션 | `uv sync --frozen` |
| `.venv-dfn` | 3.11 | 하이브리드 노이즈 제거(DeepFilterNet) | `scripts/install_dfn.sh` |
| `.venv-re` | 3.11 | 재합성(resemble-enhance) | `scripts/install_resynth.sh` |

리졸버(`core/denoise.py`)가 `.venv-dfn`/`.venv-re` 존재 여부로 엔진을
자동 감지한다. 없으면 RNNoise로 폴백(표준)하거나 재합성 모드를 숨긴다.
경로는 환경변수 `DFN_PYTHON`·`RESYNTH_PYTHON`으로 재지정 가능.

## 런타임에 다운로드되는 것 (봉인 대상 아님 — 정상)

용량·라이선스 때문에 저장소에 넣지 않고 최초 실행 시 받는다:

- **TTS·Whisper·resemble-enhance 모델** — huggingface_hub 캐시(`~/.cache/huggingface`)
- **DNSMOS 품질 모델**(.onnx) — `scripts/download_dnsmos.sh` (평가 기능에만 필요)

오프라인 사용은 이들을 한 번 받은 뒤부터 가능하다.

## 사용자 데이터 위치

- 프로필·작업 기록: `~/.noisecleaner/{profiles,history,denoise}/`
  (환경변수 `NOISECLEANER_HOME`으로 변경 가능)
- 이 폴더만 백업하면 전체 이전 가능.

## ffmpeg 경로 재지정 (봉인 배포 시)

앱 번들이 자체 ffmpeg를 지정하려면:

```bash
export NOISECLEANER_FFMPEG=/path/to/ffmpeg
```

리졸버 우선순위: `NOISECLEANER_FFMPEG` → 동봉(imageio-ffmpeg) → 시스템 PATH.

## 재현 검증 (클린룸) — 실측 완료

`scripts/verify_cleanroom.sh`가 **fresh 체크아웃 + Homebrew 경로 제거 + uv만
있는 PATH**에서 부트스트랩부터 세 엔진·클로닝까지 실제 실행하고, 사용된
바이너리 경로를 검증한다. 실측 결과 (시스템 ffmpeg/ffprobe/python3.11/12/brew
전부 `unreachable`):

| 단계 | 결과 |
|---|---|
| 메인 파이썬 | uv 관리 `.venv/bin/python3` (시스템 아님) ✓ |
| ffmpeg | 동봉 `imageio_ffmpeg/.../ffmpeg-macos-aarch64-v7.1` ✓ |
| 표준 노이즈 제거(RNNoise) | 동작 ✓ |
| 하이브리드(DFN) — 워커 uv 설치 | 동작 ✓ |
| 재합성 — 워커 uv 설치 | 동작 ✓ |
| 보이스 클로닝(mlx/whisper/TTS) | 동작 ✓ |
| 유닛 테스트 78개 | 통과 ✓ |

```bash
bash scripts/verify_cleanroom.sh   # 언제든 재실행 가능
```

### 검증이 잡아낸 실제 결함 (기록)

클린룸이 아니었으면 놓쳤을, 판매 앱을 다른 Mac에서 깨뜨렸을 결함:

- **mlx-whisper가 bare `ffmpeg`를 PATH에서 호출** — 오디오 로드 시. 동봉
  바이너리는 이름이 `ffmpeg-macos-...`라 안 잡혔다. → `ensure_ffmpeg_on_path()`가
  동봉본을 `ffmpeg` 심링크(`~/.noisecleaner/bin`)로 만들어 PATH에 얹어 해결.
  제3자 라이브러리의 bare 호출까지 커버.

## 완전 봉인 번들 (판매용 — uv도 필요 없음)

`scripts/build_bundle.sh`가 **uv·파이썬·ffmpeg가 전혀 없는 Mac에서도 그대로
도는** self-contained 배포본 `dist/NoiseCleaner/`를 만든다.

```bash
bash scripts/build_bundle.sh        # → dist/NoiseCleaner/ (약 3.7GB)
# 사용자: '노이즈클리너 실행.command' 더블클릭
```

**원리 (실증됨):** python-build-standalone는 설계상 재배치 가능. venv를
`uv venv --relocatable`로 만들고 `bin/python` 심링크를 상대경로로 고치면,
번들을 어디로 옮기든 깨끗한 PATH에서 무거운 네이티브 확장(mlx·torch)까지
로드된다. `pyvenv.cfg`의 절대 `home`은 무시된다 — 파이썬은 인터프리터
자기 위치에서 base를 찾기 때문.

**번들 구성:**

```
dist/NoiseCleaner/
├─ runtime/
│  ├─ py312/ py311/          # 동봉 파이썬 (python-build-standalone)
│  ├─ .venv/ .venv-dfn/ .venv-re/  # relocatable venv (심링크 상대화)
│  └─ bin/uv                 # uv 바이너리 (엔진 업데이트·재빌드용)
├─ core/ web/ voice/ models/ docs/  # 앱
└─ 노이즈클리너 실행.command   # 더블클릭 런처
```

**검증 완료 (실측):** 번들을 새 경로로 옮기고 `uv·python3.11/12·ffmpeg·brew`가
전부 `unreachable`인 환경(`env -i PATH=/usr/bin:/bin`)에서:

| 항목 | 결과 |
|---|---|
| 서버 부팅 + `/api/health` | clone·dfn-hybrid·resynth 전부 활성 ✓ |
| 표준 노이즈 제거 / DFN 하이브리드 | 동작 ✓ |
| 보이스 클로닝(mlx/whisper/TTS) | 동작 ✓ |
| 사용된 파이썬 / ffmpeg | 번들 내부 (시스템 아님) ✓ |

### 완전 오프라인 배포 (`--with-models`)

```bash
bash scripts/build_bundle.sh --with-models   # → 약 11GB, 네트워크 불필요
```

런타임 모델까지 전부 번들에 넣어 **네트워크 0으로** 판매·실행 가능:

| 모델 | 용도 | 동봉 방식 |
|---|---|---|
| Qwen3-TTS 1.7B/0.6B-8bit | 클로닝 | HF 캐시 → `models/hf` |
| whisper large-v3-turbo / base | 참조 받아쓰기 / 채점·가사 | HF 캐시 → `models/hf` |
| ResembleAI/resemble-enhance | 재합성 | HF 캐시 → `models/hf` |
| UTMOS (tarepan/SpeechMOS) | PNS 북극성 채점 | torch.hub → `models/torch` |
| DeepFilterNet3 · Resemblyzer | 노이즈 제거 · 화자 유사도 | 파이썬 패키지에 동봉 |
| RNNoise | 표준 노이즈 제거 | `models/` (리포 포함) |

런처가 `HF_HOME`·`TORCH_HOME`을 번들 캐시로 지정한다.

**완전 오프라인 검증 (실측):** 번들을 새 경로로 옮기고
`env -i PATH=/usr/bin:/bin HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1`,
빈 HOME(공유 캐시 차단)으로:

| 항목 | 결과 |
|---|---|
| UTMOS 로드 (네트워크 강제 차단) | ✓ |
| 서버 클론 잡 (2테이크, PNS·가사 채점) | PNS 77.1 · 가사 3단어 ✓ |
| 재합성 (resemble-enhance) | ✓ |
| CLI 클론 · 노이즈 제거 | ✓ |

- **Apple Silicon 전용** — mlx가 Metal을 쓰므로 Intel Mac·타 OS 미지원(제품 사양).
- **서명·공증** — 배포 시 codesign + notarize가 남은 단계(더블클릭 Gatekeeper 통과용).
