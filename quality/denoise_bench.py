#!/usr/bin/env python3
"""노이즈 제거 합성 벤치 — 정답이 있는 시험대 (재현 가능).

클린 음성(골든 TTS 픽스처) + 합성 팬 노이즈(고정 시드)를 알려진 SNR로 혼합해
엔진을 채점한다. 개인 녹음은 쓰지 않는다.

북극성 게이트 (사전 확정):
- TPR(말끝 보존) ≥ -1dB : 말끝이 몸통보다 1dB 이상 더 깎이면 실패
  ("노이즈 제거가 말끝을 없앤다" 청취 피드백의 정량화)
- 발화 중 SNR 개선: SNR5 입력 ≥ +5dB, SNR15 입력 ≥ +3dB
  ("말하는 중 노이즈가 남는다"의 정량화)
- 무음 잔여 ≤ -55dBFS : 말 안 할 때는 확실히 조용할 것

실측 (n=8): RNNoise TPR -2.4 / 개선 +3.1·-1.8 → 실패.
DFN 하이브리드 TPR -0.4/-0.1, 개선 +6.5/+3.9, 무음 -68/-72 → 통과.

사용: python3 quality/denoise_bench.py [--engine auto|rnnoise|dfn]
"""
import argparse
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)

GATES = {"tpr": -1.0, "gain_snr5": 5.0, "gain_snr15": 3.0, "floor": -55.0}
SR = 48_000


def _frames_db(y, sr, np):
    hop = int(sr * 0.03)
    nf = max(len(y) // hop, 1)
    return 20 * np.log10(np.maximum(
        np.sqrt((y[: nf * hop].reshape(nf, hop) ** 2).mean(axis=1)), 1e-9)), hop


def speech_chunks(y, sr, np):
    db, hop = _frames_db(y, sr, np)
    th = np.percentile(db, 90) - 30
    speech = db >= th
    chunks, start, gap = [], None, 0
    for i, s in enumerate(np.append(speech, False)):
        if s:
            if start is None:
                start = i
            gap = 0
        elif start is not None:
            gap += 1
            if gap >= 6:
                chunks.append((start * hop, (i - gap + 1) * hop))
                start = None
    return [(s, e) for s, e in chunks if e - s > sr * 0.4]


def align(out, ref, sr, np):
    n = min(len(out), len(ref), sr * 10)
    max_lag = int(sr * 0.1)
    best_lag, best = 0, -1.0
    for lag in range(-max_lag, max_lag + 1, 8):
        if lag >= 0:
            c = float(np.dot(out[lag:n], ref[: n - lag]))
        else:
            c = float(np.dot(out[: n + lag], ref[-lag:n]))
        if c > best:
            best, best_lag = c, lag
    if best_lag >= 0:
        out2 = out[best_lag:]
    else:
        out2 = np.concatenate([np.zeros(-best_lag, dtype=out.dtype), out])
    L = min(len(out2), len(ref))
    return out2[:L], ref[:L]


def score(clean, noisy, out, sr, np):
    out, clean = align(out, clean, sr, np)
    noisy = noisy[: len(clean)]
    chunks = speech_chunks(clean, sr, np)
    tail = int(sr * 0.25)

    def rms_db(x):
        return 10 * np.log10(max(float((x ** 2).mean()), 1e-12))

    tl, ml, si, so = [], [], [], []
    res_out, res_in = out - clean, noisy[: len(out)] - clean
    for s, e in chunks:
        if e - s < 3 * tail:
            continue
        tl.append(rms_db(clean[e - tail:e]) - rms_db(out[e - tail:e]))
        ml.append(rms_db(clean[s + tail:e - tail]) - rms_db(out[s + tail:e - tail]))
        si.append(rms_db(clean[s:e]) - rms_db(res_in[s:e]))
        so.append(rms_db(clean[s:e]) - rms_db(res_out[s:e]))
    cdb, _ = _frames_db(clean, sr, np)
    odb, _ = _frames_db(out, sr, np)
    pause = cdb < np.percentile(cdb, 90) - 40
    L2 = min(len(cdb), len(odb))
    floor = float(np.mean(odb[:L2][pause[:L2]])) if pause[:L2].any() else -99.0
    return {"tpr": float(np.mean(ml) - np.mean(tl)),
            "gain": float(np.mean(so) - np.mean(si)), "floor": floor}


def main():
    import numpy as np
    import soundfile as sf
    from scipy.signal import lfilter
    from core.denoise import dfn_available, run_denoise

    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", default="auto",
                    choices=["auto", "rnnoise", "dfn"])
    args = ap.parse_args()
    engine = args.engine
    if engine == "auto":
        engine = "dfn" if dfn_available() else "rnnoise"
    if engine == "dfn" and not dfn_available():
        print("DFN 미설치 — 벤치 생략 (설치: bash scripts/install_dfn.sh)")
        return

    fixtures = [os.path.join(ROOT, "tests", "fixtures", f"golden_clone_{i}.wav")
                for i in (1, 2, 3, 4)]
    rng = np.random.default_rng(42)
    rows = {5: [], 15: []}
    with tempfile.TemporaryDirectory() as wd:
        for fi, fp in enumerate(fixtures):
            clean, _ = sf.read(fp, dtype="float32")
            if clean.ndim > 1:
                clean = clean.mean(axis=1)
            # 48k 업샘플 (엔진 동작 대역)
            import librosa
            clean = librosa.resample(clean, orig_sr=24_000, target_sr=SR)
            w = rng.standard_normal(len(clean))
            n = lfilter([1.0], [1.0, -0.97], w)
            n = (n / np.sqrt((n ** 2).mean())).astype(np.float32)
            chunks = speech_chunks(clean, SR, np)
            sp = np.concatenate([clean[s:e] for s, e in chunks])
            sp_rms = float(np.sqrt((sp ** 2).mean()))
            for snr in (5, 15):
                noisy = clean + n * (sp_rms / 10 ** (snr / 20))
                nin = os.path.join(wd, f"n_{fi}_{snr}.wav")
                nout = os.path.join(wd, f"o_{fi}_{snr}.wav")
                sf.write(nin, noisy, SR)
                run_denoise(nin, nout, engine=engine)
                out, _ = sf.read(nout, dtype="float32")
                if out.ndim > 1:
                    out = out.mean(axis=1)
                rows[snr].append(score(clean, noisy, out, SR, np))

    print(f"엔진: {engine}")
    print(f"{'SNR':<5} {'TPR(말끝)':>9} {'발화중개선':>8} {'무음잔여':>8}")
    ok_all = True
    for snr in (5, 15):
        t = float(np.mean([r["tpr"] for r in rows[snr]]))
        g = float(np.mean([r["gain"] for r in rows[snr]]))
        fl = float(np.mean([r["floor"] for r in rows[snr]]))
        ok = (t >= GATES["tpr"]
              and g >= (GATES["gain_snr5"] if snr == 5 else GATES["gain_snr15"])
              and fl <= GATES["floor"])
        ok_all &= ok
        print(f"{snr:<5} {t:>+9.1f} {g:>+8.1f} {fl:>8.1f}  {'✅' if ok else '❌'}")
    print("게이트:", "✅ 통과" if ok_all else "❌ 실패")
    if not ok_all:
        sys.exit(1)


if __name__ == "__main__":
    main()
