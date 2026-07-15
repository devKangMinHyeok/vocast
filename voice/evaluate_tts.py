"""보이스 클로닝 TTS 품질 채점 스크립트.

지표 3종:
1. SIM  — 화자 유사도 (0~1). 스피커 임베딩(목소리 지문) 코사인 유사도.
          참조 목소리와 얼마나 같은 사람처럼 들리는지.
2. CER  — 글자 오류율 (%). Whisper로 받아쓰기해서 대본과 대조.
          발음이 뭉개지거나 단어를 삼키면 올라감. 낮을수록 좋음.
3. MOS  — DNSMOS OVRL (1~5). 오디오 자연스러움/품질.

사용: evaluate_tts.py <참조음성.wav> <대본.txt> <생성본1.wav> [생성본2.wav ...]
"""
import math
import os
import re
import sys

import numpy as np
import onnxruntime as ort
import librosa
import jiwer
import mlx_whisper
from resemblyzer import VoiceEncoder, preprocess_wav

HERE = os.path.dirname(os.path.abspath(__file__))
DNSMOS_MODEL = os.path.join(HERE, "dnsmos_sig_bak_ovr.onnx")
WHISPER = "mlx-community/whisper-large-v3-turbo"

p_ovr = np.poly1d([-0.06766283, 1.11546468, 0.04602535])
p_sig = np.poly1d([-0.08397278, 1.22083953, 0.0052439])
p_bak = np.poly1d([-0.13166888, 1.60915514, -0.39604546])


def dnsmos_ovrl(path, sess):
    sr = 16_000
    audio, _ = librosa.load(path, sr=sr, mono=True)
    seg_len = int(9.01 * sr)
    if len(audio) < seg_len:
        audio = np.tile(audio, math.ceil(seg_len / len(audio)))[:seg_len]
    num_hops = int(np.floor(len(audio) / sr) - 9.01) + 1
    name = sess.get_inputs()[0].name
    ovrs, sigs = [], []
    for i in range(max(num_hops, 1)):
        seg = audio[int(i * sr): int(i * sr) + seg_len]
        if len(seg) < seg_len:
            break
        out = sess.run(None, {name: seg.astype(np.float32)[np.newaxis, :]})
        sig_raw, bak_raw, ovr_raw = out[0][0]
        sigs.append(float(p_sig(sig_raw)))
        ovrs.append(float(p_ovr(ovr_raw)))
    return np.mean(sigs), np.mean(ovrs)


def normalize_ko(text):
    """한국어 CER용 정규화: 공백/문장부호 제거."""
    return re.sub(r"[^\w]", "", text, flags=re.UNICODE).lower()


def main():
    ref_path, script_path, gens = sys.argv[1], sys.argv[2], sys.argv[3:]
    script = open(script_path, encoding="utf-8").read().strip()
    script_norm = normalize_ko(script)

    encoder = VoiceEncoder()
    ref_emb = encoder.embed_utterance(preprocess_wav(ref_path))
    sess = ort.InferenceSession(DNSMOS_MODEL, providers=["CPUExecutionProvider"])

    print(f"reference: {os.path.basename(ref_path)}")
    hdr = f"{'file':<34} {'SIM':>5} {'CER%':>6} {'SIG':>5} {'MOS':>5}"
    print(hdr)
    print("-" * len(hdr))
    results = []
    for g in gens:
        emb = encoder.embed_utterance(preprocess_wav(g))
        sim = float(np.dot(ref_emb, emb))
        hyp = mlx_whisper.transcribe(g, path_or_hf_repo=WHISPER, language="ko")["text"]
        cer = jiwer.cer(script_norm, normalize_ko(hyp)) * 100
        sig, mos = dnsmos_ovrl(g, sess)
        results.append((os.path.basename(g), sim, cer, sig, mos, hyp))
        print(f"{os.path.basename(g):<34} {sim:5.3f} {cer:6.1f} {sig:5.2f} {mos:5.2f}")

    print("\n[받아쓰기 결과]")
    for name, _, cer, _, _, hyp in results:
        print(f"- {name} ({cer:.1f}%): {hyp.strip()}")


if __name__ == "__main__":
    main()
