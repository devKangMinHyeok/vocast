"""DeepFilterNet 워커 — 전용 venv(.venv-dfn, python3.11)에서 실행된다.

사용: python core/dfn_worker.py 입력.wav 출력_보호.wav 출력_풀억제.wav

하이브리드 엔진의 두 재료를 만든다:
- 보호 출력: 감쇠 상한 12dB (발화·말끝 보호 — 말끝 클리핑 방지, 실측 TPR -2.5→-0.4)
- 풀억제 출력: 상한 없음 (무음 구간용, 잔여 -120dBFS급)
"""
import sys


def main():
    in_wav, out_lim, out_unlim = sys.argv[1], sys.argv[2], sys.argv[3]
    from df.enhance import enhance, init_df, load_audio, save_audio
    model, df_state, _ = init_df(post_filter=True, log_level="ERROR")
    audio, _ = load_audio(in_wav, sr=df_state.sr())
    save_audio(out_lim, enhance(model, df_state, audio, atten_lim_db=12),
               df_state.sr())
    save_audio(out_unlim, enhance(model, df_state, audio), df_state.sr())


if __name__ == "__main__":
    main()
