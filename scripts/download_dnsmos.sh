#!/bin/bash
# DNSMOS 채점 모델 다운로드 (evaluate.py 전용, 약 1.1MB)
# 출처: Microsoft DNS-Challenge (https://github.com/microsoft/DNS-Challenge)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
URL="https://github.com/microsoft/DNS-Challenge/raw/master/DNSMOS/DNSMOS/sig_bak_ovr.onnx"
OUT="$ROOT/models/dnsmos_sig_bak_ovr.onnx"
echo "다운로드 중: $URL"
curl -sL -o "$OUT" "$URL"
echo "완료: $OUT"
