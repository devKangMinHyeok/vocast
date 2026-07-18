@echo off
REM 노이즈 클리너 실행 (Windows) — 더블클릭 런처. ⚠️ Windows 실기 검증 필요.
setlocal
set "BUNDLE=%~dp0"
set "RT=%BUNDLE%runtime"

REM Windows에서는 mlx 미설치 → 보이스 클로닝 자동 비활성, 노이즈 제거·재합성만.
set "RESYNTH_PYTHON=%RT%\.venv-re\Scripts\python.exe"
if not defined NOISECLEANER_HOME set "NOISECLEANER_HOME=%USERPROFILE%\.noisecleaner"

if exist "%BUNDLE%models\hf"    set "HF_HOME=%BUNDLE%models\hf"
if exist "%BUNDLE%models\torch" set "TORCH_HOME=%BUNDLE%models\torch"

echo 노이즈 클리너를 시작합니다...
cd /d "%BUNDLE%"
start "" http://127.0.0.1:8756
"%RT%\.venv\Scripts\python.exe" web\server.py --port 8756
