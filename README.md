# 🎙️ Vocast

[![CI](https://github.com/devKangMinHyeok/vocast/actions/workflows/ci.yml/badge.svg)](https://github.com/devKangMinHyeok/vocast/actions/workflows/ci.yml)
[![Quality Gate](https://github.com/devKangMinHyeok/vocast/actions/workflows/quality.yml/badge.svg)](https://github.com/devKangMinHyeok/vocast/actions/workflows/quality.yml)

크리에이터를 위한 **로컬 음성 스튜디오**. 한 번 등록한 **내 목소리로 원고를 자연스럽게 낭독**하고
(보이스 클로닝), 직접 녹음한 소스의 **배경 소음도 함께 제거**한다. 모든 처리가 내 컴퓨터 안에서만
이루어지고, 목소리 데이터는 서버로 올라가지 않는다.

CLI · 로컬 웹 앱 · 맥 앱, 세 가지 방식으로 쓸 수 있다.

## 🌐 웹에서 바로 쓰기 (설치 불필요)

**https://devkangminhyeok.github.io/vocast/**

ffmpeg.wasm으로 브라우저 안에서 직접 처리한다 — 파일이 서버로 전송되지 않고,
내 컴퓨터(브라우저) 밖으로 나가지 않는다. 최초 접속 시 변환 엔진(약 30MB)을 한 번 내려받는다.

## 준비물 — uv 하나면 끝

시스템에 파이썬·ffmpeg·brew가 없어도 된다. **[uv](https://docs.astral.sh/uv/)**
하나만 있으면 관리형 파이썬과 잠긴 의존성을 재현하고, ffmpeg는 휠로 동봉된다.

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh   # uv 설치 (최초 1회)
bash bootstrap.sh                                  # 클론 후 한 방 설치
```

격리 세부는 [PORTABILITY.md](PORTABILITY.md) 참고 (무엇이 봉인되고 무엇이
런타임에 다운로드되는지).

## 1) CLI로 쓰기

```bash
uv run python denoise.py input.mov                # → input_clean.mov
uv run python denoise.py input.mov -o output.mov  # 출력 이름 지정
uv run python denoise.py input.mov --boost 13     # 볼륨도 13dB 키우기
```

ffmpeg는 동봉본(imageio-ffmpeg)을 자동으로 쓴다 — 시스템 설치 불필요.

## 2) 로컬 웹 앱으로 쓰기

```bash
uv run python web/server.py
```

브라우저에서 `http://127.0.0.1:8756` 접속 → 파일을 끌어다 놓으면 끝.
서버는 로컬(127.0.0.1)에만 열리므로 파일이 외부로 나가지 않는다.

클로닝 의존성(아래)을 설치하면 두 탭이 더 활성화된다:

- **🗣️ 보이스 클로닝** — 프로필 또는 파일로 대본 낭독 생성. 생성 과정이
  실시간으로 시각화된다: 참조 분석 → **테이크 오디션**(테이크마다 운율
  점수·끝음·강약이 카드로 뜨고 최고점이 👑 채택) → 마무리. 모든 생성은
  세션으로 저장되어 목록에서 다시 듣고 내려받을 수 있다
  (`~/.vocast/history/`).
- **🎤 내 목소리** — 가이드 문장 10개(약 90초, 끝음 유형·호흡·속도·강세를
  커버하도록 설계)를 브라우저에서 바로 녹음하면 **보이스 프로필**을 만든다.
  기존 영상·음성 파일도 함께 넣을 수 있고(파일당 앞 3분 사용, 녹음 없이
  파일만으로도 가능), **소스마다 노이즈 제거를 개별 선택**할 수 있다
  (기본 켬). 억양·호흡·끝음·강세를 분석해 캐시하므로, 이후 클로닝은 참조
  준비 없이 바로 시작된다 (`~/.vocast/profiles/`).

## 3) 맥 앱으로 쓰기

```bash
bash macapp/build_app.sh                # 노이즈 제거만
bash macapp/build_app.sh --with-voice   # + 보이스 클로닝 탭 (Apple Silicon)
open dist/Vocast.app
```

더블클릭 한 번으로 서버가 켜지고 브라우저가 열린다. Dock이나 응용 프로그램 폴더에
옮겨 두고 쓰면 된다. (가상환경 생성과 flask 설치는 빌드 스크립트가 알아서 한다.)

## 어떻게 동작하나

사람 목소리만 남기도록 학습된 신경망 모델 **[RNNoise](https://jmvalin.ca/demo/rnnoise/)**
(`models/rnnoise-sh.rnnn`)에 오디오를 통과시킨다. ffmpeg의 `arnndn` 필터가 이를 실행한다.
영상 스트림은 재압축 없이 그대로 복사(`-c:v copy`)하므로 화질 손상이 없다.

## 품질을 어떻게 검증했나

깨끗한 정답 오디오가 없는 실녹음이라 **무참조 평가**를 썼다:

- **DNSMOS P.835** (Microsoft) — 사람 청취 평가를 흉내내는 AI 채점 모델.
  목소리 품질(SIG)과 소음 억제(BAK)를 따로 채점해서 "목소리는 안 상하고 소음만
  없앴나"를 판별할 수 있다.
- **노이즈 플로어 측정** — 말 안 하는 구간이 처리 후 몇 dB 조용해졌는지 직접 측정.

실제 스크린 레코딩(27.5초)으로 11가지 방식을 경쟁시킨 결과:

| 항목 | 원본 | 처리 후 |
|------|------|--------|
| SIG (목소리 품질) | 3.60 | **3.72** |
| BAK (소음 억제) | 3.97 | **4.22** |
| OVRL (종합) | 3.24 | **3.51** |
| 무음 구간 소음 | — | **-21.6dB** (약 1/10 이하) |

직접 검증해 보려면:

```bash
pip install numpy librosa onnxruntime soundfile
bash scripts/download_dnsmos.sh
python3 evaluate.py original.wav processed.wav
```

## 🗣️ 보이스 클로닝: 내 목소리로 대본 읽어주기 (Apple Silicon 전용)

목소리가 담긴 파일(영상도 됨)을 주면, 그 목소리로 대본을 읽은 오디오를 만든다.

```bash
pip install -r voice/requirements-voice.txt
python3 voice/clone_say.py --ref 내목소리.mov --text "안녕하세요" -o out.wav
python3 voice/clone_say.py --ref 내목소리.wav --script 대본.txt -o out.wav --fast
```

파이프라인: 오디오 추출 → **RNNoise 노이즈 제거**(위 도구 재사용) → Whisper 받아쓰기 →
**Qwen3-TTS 1.7B**(Apache 2.0)로 생성. 전부 로컬에서 실행된다.

"지표 먼저 → 후보 경쟁 → 최고 선택" 방식으로 설정을 확정했다.
화자 유사도(SIM, 스피커 임베딩 코사인) / 글자 오류율(CER, Whisper 받아쓰기 대조) /
자연스러움(DNSMOS)으로 5개 조합을 채점한 결과:

| 지표 | 우승 설정 (1.7B + 노이즈 제거 참조) | 기준 |
|------|------|------|
| SIM | **0.917~0.945** | 본인 육성끼리 비교 시 0.909 |
| CER | **0%** | 숫자·영어 혼용 대본 포함 |
| MOS | **3.50** | 원본 녹음 3.24 |

주요 발견: 참조 음성을 노이즈 제거하면 모든 조합에서 SIM이 오른다 (+0.02).
평가 재현은 `voice/evaluate_tts.py` 참고.

> ⚠️ **본인 목소리이거나 명시적으로 동의받은 목소리만** 클로닝할 것.
> 타인 목소리 무단 클로닝은 법적 문제와 악용(보이스피싱 등) 소지가 있다.
> AI 생성 음성을 콘텐츠에 쓸 때는 고지하는 것을 권장한다.

## 아키텍처: 앱 계층과 코어의 분리

```
┌─ 앱 계층 (얇게) ──────────────────────────────────┐
│  denoise.py(CLI)   voice/clone_say.py(CLI)        │
│  web/server.py(HTTP)   macapp(실행기)   quality(CI)│
└───────────────┬───────────────────────────────────┘
                │  함수 호출만 (단방향 의존)
┌───────────────▼───────────────────────────────────┐
│  core/  — 순수 로직                                │
│  audio(ffmpeg) · denoise(RNNoise) · clone(TTS)     │
│  metrics(SIM/CER/MOS/VCS + 게이트)                 │
└───────────────────────────────────────────────────┘
```

**규칙** (tests/test_architecture.py 가 CI에서 강제):
- 앱 계층은 ffmpeg·모델을 직접 만지지 않는다 — `subprocess` 금지, core 호출만.
- core는 flask·argparse·print를 모른다 — HTTP 코드/CLI 파싱/화면 출력은 앱 몫.
- 의존은 앱 → core 단방향. core가 앱 계층을 임포트하면 테스트가 깨진다.

새 인터페이스(예: 메뉴바 앱, 자동화 스크립트)를 만들 때는 core 함수 3개만 알면 된다:
`run_denoise(in, out, boost)` · `clone_voice(ref, text, out, fast)` · `evaluate_clone(ref, script, gen)`

## 품질 시스템

품질은 느낌이 아니라 숫자로 지킨다 — **[QUALITY.md](QUALITY.md)** 참고.

- **북극성 지표 VCS** (0~100): 화자 유사도·대본 정확도·자연스러움의 가중 합성. 현재 약 91~93점.
- **CI 2단**: 모든 푸시마다 유닛 테스트(`ci.yml`, ~1분) + 주 1회/수동으로
  실제 생성→채점→게이트(`quality.yml`, Apple Silicon 러너).
- 게이트: SIM ≥ 0.85, CER ≤ 3%, MOS ≥ 3.0, VCS ≥ 85 — 미달이면 CI 실패.

## 폴더 구성

```
core/                 ★ 핵심 로직 패키지 (여기만 보면 됨)
  audio.py              ffmpeg 래퍼
  denoise.py            노이즈 제거 파이프라인
  clone.py              보이스 클로닝 파이프라인
  metrics.py            평가지표 SIM/CER/MOS + 북극성 VCS + 게이트
denoise.py            노이즈 제거 CLI (얇은 래퍼)
voice/clone_say.py    보이스 클로닝 CLI (얇은 래퍼)
voice/evaluate_tts.py 클로닝 결과물 채점 CLI
web/                  로컬 웹 서버(Flask) + UI (노이즈 제거 / 클로닝 탭)
macapp/build_app.sh   맥 앱(.app) 빌드 스크립트
tests/                유닛 테스트 + 픽스처(AI 생성 가상 목소리)
quality/              품질 회귀 평가 (run_eval.py + 테스트 대본 세트)
.github/workflows/    CI (ci.yml 유닛 / quality.yml 품질 게이트)
models/               RNNoise 모델
evaluate.py           노이즈 제거 채점 스크립트
scripts/              DNSMOS 채점 모델 다운로드
```

## 크레딧 & 라이선스

- 이 프로젝트: MIT License
- [RNNoise](https://github.com/xiph/rnnoise) (Xiph.Org, BSD-3-Clause) —
  모델 파일은 [rnnoise-models](https://github.com/GregorR/rnnoise-models)의
  `somnolent-hogwash` (RNNoise와 동일 라이선스)
- [DNSMOS](https://github.com/microsoft/DNS-Challenge) (Microsoft) — 평가용,
  저장소에 포함하지 않고 스크립트로 내려받는다
