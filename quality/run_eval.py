#!/usr/bin/env python3
"""보이스 클로닝 품질 회귀 평가 (CI 품질 게이트의 본체).

픽스처 목소리(tests/fixtures/ref_fixture.wav — AI 생성, 권리 문제 없음)로
테스트 대본 세트(quality/testset.txt)를 낭독 생성하고, 지표로 채점한 뒤
게이트(core.metrics.GATES) 미달이면 종료 코드 1 → CI 실패.

사용:
  python3 quality/run_eval.py                # 기본 모델 (1.7B)
  python3 quality/run_eval.py --fast         # 0.6B, 빠름 (릴리스 전 로컬 기준)
  python3 quality/run_eval.py --golden       # 생성 없이 커밋된 골든 샘플만 채점
                                             # (GPU 없는 호스티드 CI용 — 평가 스택 회귀 감지)
  python3 quality/run_eval.py --report r.json

골든 샘플 갱신(파이프라인 개선으로 소리가 좋아졌을 때):
  로컬에서 재생성해 tests/fixtures/golden_clone_N.wav 를 교체 커밋한다.
"""
import argparse
import json
import os
import statistics
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)

from core.clone import prepare_reference, synthesize_best  # noqa: E402
from core.metrics import (GATES, PNS_ITEM_MIN, check_gates,  # noqa: E402
                          evaluate_clone, voice_clone_score)

FIXTURE = os.path.join(ROOT, "tests", "fixtures", "ref_fixture.wav")
TESTSET = os.path.join(HERE, "testset.txt")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fast", action="store_true", help="0.6B 모델 사용 (CI 기본)")
    ap.add_argument("--report", help="JSON 리포트 저장 경로")
    ap.add_argument("--no-gate", action="store_true", help="게이트 실패해도 종료코드 0")
    ap.add_argument("--limit", type=int, default=0,
                    help="대본 N개만 평가 (호스티드 러너 스모크 게이트용, 0=전체)")
    ap.add_argument("--golden", action="store_true",
                    help="생성 없이 커밋된 골든 샘플 채점 (GPU 없는 CI용)")
    args = ap.parse_args()

    scripts = [line.strip() for line in open(TESTSET, encoding="utf-8")
               if line.strip()]
    if args.limit:
        scripts = scripts[:args.limit]
    results = []

    with tempfile.TemporaryDirectory() as wd:
        print("· 픽스처 참조 준비 (노이즈 제거 + 창 선택 + 받아쓰기)…")
        ref_wav, ref_text, natural_wav = prepare_reference(FIXTURE, wd)
        for i, script in enumerate(scripts, 1):
            if args.golden:
                out = os.path.join(ROOT, "tests", "fixtures",
                                   f"golden_clone_{i}.wav")
                if not os.path.exists(out):
                    print(f"· [{i}/{len(scripts)}] 골든 샘플 없음 — 건너뜀")
                    continue
                print(f"· [{i}/{len(scripts)}] 골든 채점: {script[:30]}…")
            else:
                out = os.path.join(wd, f"gen_{i}.wav")
                print(f"· [{i}/{len(scripts)}] 생성(best-of-N): {script[:30]}…")
                synthesize_best(script, ref_wav, ref_text, natural_wav, out,
                                fast=args.fast, takes=5)
            r = evaluate_clone(ref_wav, script, out, natural_wav=natural_wav)
            r["script"] = script
            results.append(r)

    if not results:
        sys.exit("평가할 샘플이 없습니다 (골든 파일 누락?)")

    agg = {k: statistics.mean(r[k] for r in results)
           for k in ("sim", "cer", "mos", "pns")}
    agg["vcs"] = voice_clone_score(agg["sim"], agg["cer"], agg["mos"])
    ok, failures = check_gates(agg)
    pns_min = min(r["pns"] for r in results)
    if pns_min < PNS_ITEM_MIN:
        ok = False
        failures.append(f"PNS 항목 최저 {pns_min:.1f} < {PNS_ITEM_MIN}")

    hdr = f"{'#':<3} {'SIM':>6} {'CER%':>6} {'MOS':>5} {'VCS':>6} {'PNS':>6}  script"
    print("\n" + hdr)
    print("-" * 66)
    for i, r in enumerate(results, 1):
        print(f"{i:<3} {r['sim']:6.3f} {r['cer']:6.1f} {r['mos']:5.2f} "
              f"{r['vcs']:6.1f} {r['pns']:6.1f}  {r['script'][:26]}…")
    print("-" * 66)
    print(f"평균  SIM {agg['sim']:.3f} | CER {agg['cer']:.1f}% | MOS {agg['mos']:.2f} | "
          f"VCS {agg['vcs']:.1f} | PNS(운율 북극성) {agg['pns']:.1f} (min {pns_min:.1f})")
    print(f"게이트 {GATES} + PNS최저 {PNS_ITEM_MIN} → "
          f"{'✅ 통과' if ok else '❌ 실패: ' + '; '.join(failures)}")

    if args.report:
        with open(args.report, "w", encoding="utf-8") as f:
            json.dump({"aggregate": agg, "gates": GATES, "pass": ok,
                       "failures": failures, "results": results},
                      f, ensure_ascii=False, indent=2)
        print(f"리포트 저장: {args.report}")

    if not ok and not args.no_gate:
        sys.exit(1)


if __name__ == "__main__":
    main()
