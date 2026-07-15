# 🎙️ Noise Cleaner (denoise-app)

영상·음성에서 **목소리는 그대로 두고 배경 소음(백색소음, 팬 소리 등)만 제거**하는 로컬 도구.
모든 처리가 내 컴퓨터 안에서만 이루어지고, 원본 파일은 절대 수정되지 않는다.

CLI · 로컬 웹 앱 · 맥 앱, 세 가지 방식으로 쓸 수 있다.

## 🌐 웹에서 바로 쓰기 (설치 불필요)

**https://devkangminhyeok.github.io/denoise-app/**

ffmpeg.wasm으로 브라우저 안에서 직접 처리한다 — 파일이 서버로 전송되지 않고,
내 컴퓨터(브라우저) 밖으로 나가지 않는다. 최초 접속 시 변환 엔진(약 30MB)을 한 번 내려받는다.

## 준비물

```bash
brew install ffmpeg
```

## 1) CLI로 쓰기

```bash
python3 denoise.py input.mov                # → input_clean.mov
python3 denoise.py input.mov -o output.mov  # 출력 이름 지정
python3 denoise.py input.mov --boost 13     # 볼륨도 13dB 키우기
```

의존성 없음 — 파이썬 표준 라이브러리 + ffmpeg만으로 동작.

## 2) 로컬 웹 앱으로 쓰기

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python3 web/server.py
```

브라우저에서 `http://127.0.0.1:8756` 접속 → 파일을 끌어다 놓으면 끝.
서버는 로컬(127.0.0.1)에만 열리므로 파일이 외부로 나가지 않는다.

## 3) 맥 앱으로 쓰기

```bash
bash macapp/build_app.sh
open dist/NoiseCleaner.app
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

## 폴더 구성

```
denoise.py            CLI 본체 (공용 ffmpeg 파이프라인 포함)
evaluate.py           품질 채점 스크립트 (선택)
models/               RNNoise 모델
web/                  로컬 웹 서버(Flask) + UI
macapp/build_app.sh   맥 앱(.app) 빌드 스크립트
scripts/              DNSMOS 채점 모델 다운로드
```

## 크레딧 & 라이선스

- 이 프로젝트: MIT License
- [RNNoise](https://github.com/xiph/rnnoise) (Xiph.Org, BSD-3-Clause) —
  모델 파일은 [rnnoise-models](https://github.com/GregorR/rnnoise-models)의
  `somnolent-hogwash` (RNNoise와 동일 라이선스)
- [DNSMOS](https://github.com/microsoft/DNS-Challenge) (Microsoft) — 평가용,
  저장소에 포함하지 않고 스크립트로 내려받는다
