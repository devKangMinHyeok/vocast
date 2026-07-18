#!/bin/bash
# 노이즈 클리너 실행 — 더블클릭용 런처.
# 번들 안의 파이썬만으로 돈다. 시스템에 uv·파이썬·ffmpeg가 없어도 된다.
set -e
BUNDLE="$(cd "$(dirname "$0")" && pwd)"
RT="$BUNDLE/runtime"

# 전용 엔진 파이썬을 번들 경로로 지정 (core가 이 환경변수를 우선 읽음)
export DFN_PYTHON="$RT/.venv-dfn/bin/python3"
export RESYNTH_PYTHON="$RT/.venv-re/bin/python3"
# 사용자 데이터(프로필·작업 기록)는 홈에 (번들을 지워도 보존)
: "${NOISECLEANER_HOME:=$HOME/.noisecleaner}"; export NOISECLEANER_HOME

# 오프라인 모델 동봉본이 있으면 그것을 캐시로 사용 (네트워크 불필요)
[ -d "$BUNDLE/models/hf" ]    && export HF_HOME="$BUNDLE/models/hf"
[ -d "$BUNDLE/models/torch" ] && export TORCH_HOME="$BUNDLE/models/torch"

PORT=8756
echo "노이즈 클리너를 시작합니다… (최초 실행 시 음성 모델을 내려받습니다)"
cd "$BUNDLE"
"$RT/.venv/bin/python" web/server.py --port "$PORT" &
SERVER=$!
# 서버가 뜨면 브라우저 열기
for _ in $(seq 1 60); do
  if curl -s "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then
    open "http://127.0.0.1:$PORT"; break
  fi
  sleep 1
done
echo "브라우저에서 http://127.0.0.1:$PORT 를 여세요. (이 창을 닫으면 종료됩니다)"
wait $SERVER
