"""상주 TTS 워커 — 모델을 1회만 로드하고 stdin으로 생성 요청을 반복 처리.

배경: CLI 서브프로세스 방식은 테이크마다 모델을 재로드한다 (실측 ~10초/회 —
6테이크면 1분 낭비). 이 워커는 JSON 라인 프로토콜로 요청을 받아 모델을
메모리에 유지한 채 생성한다.

프로토콜 (stdin → stdout, 한 줄 JSON):
  요청: {"model": .., "text": .., "ref_audio": .., "ref_text": ..,
         "out_dir": .., "prefix": ..}
  응답: {"ok": true} | {"ok": false, "error": ".."}
  종료: {"cmd": "quit"}
"""
import json
import os
import sys


def main():
    # 프로토콜 오염 방지: mlx_audio가 로드 로그를 stdout에 찍으므로,
    # 프로토콜 전용 fd를 확보하고 stdout은 stderr로 돌린다 (실측 사고 대응).
    proto = os.fdopen(os.dup(1), "w")
    os.dup2(2, 1)
    sys.stdout = sys.__stdout__ = os.fdopen(1, "w")

    model_obj, model_name = None, None
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            if req.get("cmd") == "quit":
                break
            if model_obj is None or model_name != req["model"]:
                from mlx_audio.tts.utils import load_model
                from huggingface_hub import snapshot_download
                from pathlib import Path
                path = snapshot_download(req["model"])
                model_obj = load_model(Path(path))
                model_name = req["model"]
            from mlx_audio.tts.generate import generate_audio
            generate_audio(
                text=req["text"], model=model_obj,
                ref_audio=req["ref_audio"], ref_text=req["ref_text"],
                output_path=req["out_dir"], file_prefix=req["prefix"],
                join_audio=True, audio_format="wav",
                temperature=req.get("temperature", 0.7), verbose=False)
            proto.write(json.dumps({"ok": True}) + "\n")
            proto.flush()
        except Exception as e:  # 요청 단위 실패 보고 (워커는 계속)
            proto.write(json.dumps({"ok": False, "error": str(e)[-300:]})
                        + "\n")
            proto.flush()


if __name__ == "__main__":
    main()
