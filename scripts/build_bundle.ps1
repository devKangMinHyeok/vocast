# 완전 봉인 번들 빌드 (Windows) — build_bundle.sh 의 Windows 대응본.
#
# ⚠️ 상태: 초안. macOS에서 작성되어 아직 Windows 실기에서 검증되지 않음.
#    Windows 머신(또는 windows-latest CI)에서 실행·검증한 뒤 배포에 쓸 것.
#
# 산출물 dist/NoiseCleaner/ 는 uv·파이썬이 없는 Windows에서도 도는 self-
# contained 배포본. Windows에서는 mlx가 설치되지 않으므로 보이스 클로닝은
# 자동 비활성(clone_available()==False)되고 노이즈 제거·재합성만 담긴다.
#
# 원리는 macOS 판과 동일: python-build-standalone(재배치 가능) + relocatable
# venv + 동봉 ffmpeg(imageio-ffmpeg). 단, Windows venv는 심링크가 아니라
# python.exe 복사/런처를 쓰므로 uv --relocatable 로 처리한다.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Dist = Join-Path $Root "dist\NoiseCleaner"
$RT   = Join-Path $Dist "runtime"

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Error "빌드에는 uv 필요: https://docs.astral.sh/uv/getting-started/installation/"
}

Write-Host "▸ 초기화: $Dist"
if (Test-Path $Dist) { Remove-Item -Recurse -Force $Dist }
New-Item -ItemType Directory -Force -Path $RT | Out-Null

Write-Host "▸ 파이썬 런타임 동봉 (3.12)"
$py312 = Split-Path -Parent (Split-Path -Parent (uv python find 3.12))
Copy-Item -Recurse "$py312\*" (Join-Path $RT "py312")

Write-Host "▸ 메인 환경 (.venv) — 잠긴 의존성 (Windows에선 mlx 자동 제외)"
uv venv --relocatable --python (Join-Path $RT "py312\python.exe") (Join-Path $RT ".venv")
uv export --frozen --no-dev --no-emit-project -o (Join-Path $Dist ".reqs.txt")
$env:VIRTUAL_ENV = Join-Path $RT ".venv"
uv pip install -q -r (Join-Path $Dist ".reqs.txt")
Remove-Item (Join-Path $Dist ".reqs.txt")

# 재합성 엔진(.venv-re): Windows torch 휠. DFN(.venv-dfn)은 Windows 휠 확인 필요.
Write-Host "▸ 재합성 엔진 (.venv-re) — Windows torch"
uv venv --relocatable --python "3.11" (Join-Path $RT ".venv-re")
$env:VIRTUAL_ENV = Join-Path $RT ".venv-re"
uv pip install -q resemble-enhance --no-deps
uv pip install -q torch torchaudio "numpy<2" librosa soundfile rich tqdm resampy tabulate omegaconf pandas matplotlib huggingface_hub
# deepspeed 스텁: _deepspeed_stub 의 Windows 대응 필요 (site-packages 경로)

Write-Host "▸ 앱 코드·모델 복사"
foreach ($d in "core","web","voice","models","docs") { Copy-Item -Recurse (Join-Path $Root $d) (Join-Path $Dist $d) }
foreach ($f in "denoise.py","evaluate.py","pyproject.toml","uv.lock","README.md","PORTABILITY.md") {
    Copy-Item (Join-Path $Root $f) $Dist
}

Write-Host "▸ 런처 생성"
Copy-Item (Join-Path $PSScriptRoot "launcher.bat") (Join-Path $Dist "노이즈클리너 실행.bat")

Write-Host "✅ (초안) 번들 생성: $Dist  — Windows 실기 검증 후 배포할 것"
Write-Host "   미검증 항목: relocatable venv 재배치, DFN Windows 휠, deepspeed 스텁 경로, 런처"
