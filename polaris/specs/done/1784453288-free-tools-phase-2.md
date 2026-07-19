---
type: spec
id: 1784453288
goal: 1784452723-organic-tools-traffic
related_issues: []
branch: feat/1784453288
created: 2026-07-19
weak_dimensions: []
---

# free-tools-phase-2

## What changes (S1)

Web Audio/MediaRecorder 기반 도구 3종 추가(라이브): mic-test(레벨미터+라이브파형+5초
샘플), voice-recorder(녹음+트림+WAV), silence-remover(무음 자동탐지/수동 트림+WAV).
공유 오디오 헬퍼(app/tools/lib/audio.ts: decode/WAV 인코딩/무음 탐지/피크)와 캔버스
컴포넌트(app/tools/_audio.tsx: LiveWave/WavePeaks/LevelMeter/useLevel). ffmpeg 불필요.

## Done criteria (S2)

빌드 성공, 5개 도구 SSG 프리렌더, 3개 신규 페이지 JSON-LD 풀세트+canonical+sitemap 확인,
empty 상태 렌더 확인. (완료)

## Out of scope (S3)

Phase 3(loudness normalizer, format converter, ffmpeg.wasm). MP3 다운로드(현재 WAV만).
mic/파일 실처리 라이브 스팟체크는 배포 후(권한/실파일 필요).

## Why now (S4)

Phase 1에 이어 라이브 도구 수를 늘려 인덱스/유입 표면을 키움.

## User / consumer (S5)

크리에이터/팟캐스터 + 검색/AI 크롤러.

## Riskiest assumption (S6)

브라우저 getUserMedia/MediaRecorder/decodeAudioData가 대상 사용자 환경에서 안정 동작.

## Implementation notes

로컬 검증: 빌드 OK, 5 SSG, 신규 3개 JSON-LD(WebApplication/HowTo/FAQPage/Breadcrumb)+
canonical(vocast.me)+sitemap 확인, silence-remover empty 렌더 확인. 실처리(마이크/실파일)는
배포 후 라이브 스팟체크 예정.
