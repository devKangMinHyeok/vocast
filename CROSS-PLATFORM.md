# 크로스플랫폼 (Mac 풀기능 · Windows 축소판)

## 기능 매트릭스

| 기능 | 엔진 | macOS (Apple Silicon) | Windows / Intel / Linux |
|------|------|:---:|:---:|
| 🧹 노이즈 제거 (표준 RNNoise) | ffmpeg | ✅ | ✅ |
| 🧹 노이즈 제거 (DFN 하이브리드) | DeepFilterNet (torch) | ✅ | ✅ |
| ✨ 재합성 | resemble-enhance (torch) | ✅ | ✅ |
| 🗣️ 보이스 클로닝 | Qwen3-TTS (**mlx**) | ✅ | ❌ |
| 받아쓰기·가사·PNS 채점 | Whisper (**mlx**) | ✅ | ❌ |

**왜 클로닝은 Mac 전용인가:** MLX는 Apple이 자사 GPU(Metal)용으로 만든
프레임워크로 Windows·Intel·Linux에 설치되지 않는다. 우리 보이스 클로닝
파이프라인(TTS + Whisper)이 여기에 묶여 있다.

## 우아한 축소 (graceful degradation) — 검증됨

- `pyproject.toml`에서 `mlx-*`를 플랫폼 마커로 조건부 설치
  (`sys_platform == 'darwin' and platform_machine == 'arm64'`) →
  **다른 OS에서 `uv sync`가 성공**하고 mlx만 빠진다.
- 코드에 top-level mlx import가 없어(전부 lazy) mlx 없이도 앱이 import된다.
- `clone_available()`가 mlx 유무를 감지 → 없으면 클로닝 API가 501/400으로
  막히고, 웹 UI는 클로닝·프로필 탭을 비활성 + "Apple Silicon 전용" 안내.
- `/api/health`가 `platform`·`apple_silicon`을 노출해 UI가 이유를 표시.

**실측 (mlx 제거 환경):** 앱 import ✓, `clone_available False`,
노이즈 제거(DFN) ✓, 재합성 ✓, 서버 health `clone:false`,
클론 잡은 "mlx-audio 미설치"로 차단 ✓.
Windows CI(`windows-latest`)에서 `uv sync --frozen` + import + 테스트로
자동 검증한다.

## 패키징

| | macOS | Windows |
|--|--|--|
| 빌드 | `scripts/build_bundle.sh [--with-models]` (검증됨) | `scripts/build_bundle.ps1` (**초안, 실기 검증 필요**) |
| 런처 | `노이즈클리너 실행.command` | `노이즈클리너 실행.bat` (초안) |
| 파이썬·ffmpeg | 동봉 (python-build-standalone + imageio-ffmpeg) | 동봉 (동일 원리) |
| 서명 | codesign + notarize | Authenticode 코드 서명 |

### Windows 빌드에서 아직 검증 안 된 것

macOS에서 작성했으므로 다음은 **Windows 실기(또는 windows-latest 러너)에서
빌드·검증한 뒤** 배포해야 한다:

1. relocatable venv 재배치 — Windows는 심링크 대신 `python.exe` 복사/런처.
   uv `--relocatable`이 처리하지만 이동 후 실동작 확인 필요.
2. **DeepFilterNet Windows 휠** — 있으면 DFN 하이브리드, 없으면 RNNoise 폴백.
   (`.venv-dfn` 설치가 Windows에서 되는지 확인)
3. deepspeed 스텁의 site-packages 경로 (Windows 경로 구분자).
4. `.bat` 런처 동작·브라우저 자동 열기.

## 향후: Windows에서도 클로닝 (선택)

Windows에 클로닝을 넣으려면 MLX 대신 크로스플랫폼 백엔드로 교체해야 한다
(받아쓰기 → faster-whisper, TTS → torch 기반). 단, 품질 시스템(PNS·테이크
선별·운율 보정)이 Qwen3-TTS-mlx 출력에 맞춰 튜닝돼 있어 **전면 재검증**이
필요하다. 현재 범위(Windows 축소판)에서는 제외.
