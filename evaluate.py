"""노이즈 제거 품질 평가 스크립트 (선택 도구).

"잘 됐다"를 숫자로 검증한다. 깨끗한 정답 오디오가 없어도 되는 무참조 방식.

지표:
1. DNSMOS P.835 (Microsoft) — AI가 사람 청취 평가를 흉내내 매기는 점수 (1~5점)
   - SIG: 목소리 자체 품질 / BAK: 배경 소음 억제 / OVRL: 종합
2. 노이즈 플로어 감소량(dB) — 말 안 하는 구간이 얼마나 조용해졌는지
3. 음성 레벨 변화(dB) — 말하는 구간 크기 보존 정도

준비:
  pip install numpy librosa onnxruntime soundfile
  bash scripts/download_dnsmos.sh   # 채점 모델 다운로드

사용:
  python3 evaluate.py 원본.wav 처리본1.wav [처리본2.wav ...]
"""
import math
import os
import sys

import numpy as np
import librosa
import onnxruntime as ort

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = os.path.join(HERE, "models", "dnsmos_sig_bak_ovr.onnx")
SR_DNSMOS = 16_000
INPUT_LENGTH = 9.01  # seconds, DNSMOS 모델 입력 길이

# Microsoft dnsmos_local.py 의 보정 다항식 (raw 출력 -> MOS 점수)
p_ovr = np.poly1d([-0.06766283, 1.11546468, 0.04602535])
p_sig = np.poly1d([-0.08397278, 1.22083953, 0.0052439])
p_bak = np.poly1d([-0.13166888, 1.60915514, -0.39604546])


def dnsmos(path, sess):
    audio, _ = librosa.load(path, sr=SR_DNSMOS, mono=True)
    seg_len = int(INPUT_LENGTH * SR_DNSMOS)
    if len(audio) < seg_len:
        audio = np.tile(audio, math.ceil(seg_len / len(audio)))[:seg_len]
    num_hops = int(np.floor(len(audio) / SR_DNSMOS) - INPUT_LENGTH) + 1
    name = sess.get_inputs()[0].name
    sigs, baks, ovrs = [], [], []
    for i in range(max(num_hops, 1)):
        seg = audio[int(i * SR_DNSMOS): int(i * SR_DNSMOS) + seg_len]
        if len(seg) < seg_len:
            break
        out = sess.run(None, {name: seg.astype(np.float32)[np.newaxis, :]})
        sig_raw, bak_raw, ovr_raw = out[0][0]
        sigs.append(float(p_sig(sig_raw)))
        baks.append(float(p_bak(bak_raw)))
        ovrs.append(float(p_ovr(ovr_raw)))
    return np.mean(sigs), np.mean(baks), np.mean(ovrs)


def frame_rms_db(x, sr, frame_ms=100):
    n = int(sr * frame_ms / 1000)
    nf = len(x) // n
    frames = x[: nf * n].reshape(nf, n)
    rms = np.sqrt((frames ** 2).mean(axis=1))
    return 20 * np.log10(np.maximum(rms, 1e-9))


def speech_pause_masks(ref_db):
    """원본의 프레임 에너지로 말함/쉼 구간 판정 (디지털 무음은 제외)."""
    valid = ref_db > -70
    v = ref_db[valid]
    lo, hi = np.percentile(v, 20), np.percentile(v, 75)
    return valid & (ref_db >= hi), valid & (ref_db <= lo)


def physical_metrics(orig_path, proc_path, sr=48_000):
    o, _ = librosa.load(orig_path, sr=sr, mono=True)
    p, _ = librosa.load(proc_path, sr=sr, mono=True)
    L = min(len(o), len(p))
    odb, pdb = frame_rms_db(o[:L], sr), frame_rms_db(p[:L], sr)
    L2 = min(len(odb), len(pdb))
    odb, pdb = odb[:L2], pdb[:L2]
    speech, pause = speech_pause_masks(odb)

    def avg_db(db, mask):
        lin = 10 ** (db[mask] / 10)
        return 10 * np.log10(np.maximum(lin.mean(), 1e-18))

    return {
        "noise_reduction": avg_db(odb, pause) - avg_db(pdb, pause),
        "speech_level_change": avg_db(pdb, speech) - avg_db(odb, speech),
    }


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    if not os.path.exists(MODEL):
        sys.exit("DNSMOS 모델이 없습니다. 먼저 실행: bash scripts/download_dnsmos.sh")
    orig, candidates = sys.argv[1], sys.argv[2:]
    sess = ort.InferenceSession(MODEL, providers=["CPUExecutionProvider"])

    rows = [(os.path.basename(orig), *dnsmos(orig, sess), 0.0, 0.0)]
    for c in candidates:
        pm = physical_metrics(orig, c)
        rows.append((os.path.basename(c), *dnsmos(c, sess),
                     pm["noise_reduction"], pm["speech_level_change"]))

    hdr = f"{'file':<38} {'SIG':>5} {'BAK':>5} {'OVRL':>5} {'NR(dB)':>7} {'ΔSPCH':>6}"
    print(hdr)
    print("-" * len(hdr))
    for r in rows:
        print(f"{r[0]:<38} {r[1]:5.2f} {r[2]:5.2f} {r[3]:5.2f} {r[4]:7.1f} {r[5]:6.1f}")


if __name__ == "__main__":
    main()
