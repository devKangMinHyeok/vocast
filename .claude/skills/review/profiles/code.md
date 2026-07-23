# Code Review Profile

Vocast 스택(Next.js App Router 정적 export, React + TS, Timbre DS, 파이썬 엔진)에서 코드
정확성과 유지보수성을 본다.

## 파일 필터
- `landing/**/*.{ts,tsx}` (로직)
- `packages/design-system/src/**/*.{ts,tsx}`
- `packages/voxa/**/*.py`
- `landing/app/sitemap.ts`, `landing/app/robots.ts`, `landing/lib/*.ts`

## 체크리스트

### 이중언어 라우팅/링크 안전성 (가장 흔한 버그원)
- [ ] 내부 링크에 `localePath(lang, path)`를 썼는가? (ko 페이지에서 en 경로로 새는 교차로케일 방지)
- [ ] 절대 URL(메타/사이트맵/OG/JSON-LD)은 `absLocale(lang, path)`/`abs()`/`absFromAsset()`인가?
- [ ] 섹션/본문에 카피를 하드코딩하지 않고 `lib/i18n` 사전(`getDict(lang)`)에서 읽는가?
      한국어를 임의 기계번역해 채우지 않았는가? (핸드오프 전까지 영어 폴백)
- [ ] 이벤트 핸들러/상태/effect가 있는 컴포넌트에 `"use client"`가 있는가? (서버 컴포넌트에서
      onClick 등은 빌드 에러)
- [ ] 런타임 전용 API(window, document)를 서버 렌더 경로에서 직접 호출하지 않는가?
- [ ] 새 공개 라우트를 추가했으면 en/ko 두 로케일로 `app/sitemap.ts`에 반영했는가?

### 정확성/타입
- [ ] 미사용 import/변수/데드코드가 없는가?
- [ ] `any` 남발 없이 타입이 좁혀졌는가? 옵셔널 체이닝/기본값이 적절한가?
- [ ] 에러/빈 배열/undefined 경계가 처리되는가?

### 일관성
- [ ] 사이트 메타/URL은 `lib/site.ts`를 통하는가? (하드코딩 URL 금지)
- [ ] 구조화 데이터는 `lib/schema.ts`를 재사용하는가?
- [ ] 주변 코드의 네이밍/스타일/주석 밀도와 맞는가?

### 파이썬 엔진
- [ ] 품질 게이트(SIM/CER/MOS/PNS 등)에 영향 주는 변경이면 게이트/골든 갱신이 따라오는가?
- [ ] 번들 이식성(uv 봉인, 동봉 ffmpeg)을 깨는 시스템 의존이 새로 생기지 않았는가?

### 검증
- [ ] landing 변경은 `cd landing && pnpm exec next build`로 통과하는가? (en/ko 라우트 생성 확인)
- [ ] 타입체크 `pnpm exec tsc --noEmit`가 깨지지 않는가?

## 심각도 가이드
- Critical: 빌드 실패, 404 유발 라우팅, 런타임 크래시 경로
- Warning: 타입 느슨함, 데드코드, 하드코딩 URL
- Suggestion: 리팩터/네이밍/주석
