---
name: landing
description: Vocast 랜딩/블로그(Next.js App Router, Vercel 루트 배포, 이중언어 EN/KO) 구조와 라우팅, 로케일 링크 규칙, SEO 배선. 랜딩 페이지 작업 시 참조.
---

# Landing 스킬

`landing/`은 Next.js(App Router) 마케팅 랜딩 + 블로그. Vercel + 커스텀 도메인 vocast.me
루트 배포(basePath 없음). 영어 우선 + 한국어 지원(이중언어): 영어는 루트(`/`), 한국어는
`/ko/`. UI 규칙은 `/timbre-design` 참조.

## 언제 쓰나
- 랜딩 섹션/블로그 추가·수정, 라우팅·링크 작업, SEO/메타 배선, i18n 카피 작업

## 이중언어 아키텍처 (필독)
- **라우트 그룹 2개, 루트 레이아웃 2개**: `app/(en)/`(URL 접두 없음 → 루트) + `app/(ko)/ko/`.
  각 그룹이 자체 루트 레이아웃(`<html lang="en">` / `<html lang="ko">`)을 가진다.
  라우트 그룹 `(en)`/`(ko)`는 URL에 영향 없음. 최상위 `app/layout.tsx`는 없다.
- **페이지 본문은 공유**: 홈은 `app/_pages/HomeBody.tsx`, 블로그/툴은
  `app/blog/_index-body.tsx`·`_post-body.tsx`, `app/tools/_index-body.tsx`·`_slug-body.tsx`.
  각 라우트 파일은 `lang`만 바꿔 이 본문을 렌더하는 얇은 껍데기 + 메타.
- **카피 사전**: `lib/i18n/{en,ko}.ts`(+ `index.ts`의 `getDict(lang)`). 섹션은 `lang`을 받아
  사전에서 읽는다(하드코딩 금지). `ko.ts`는 현재 영어 폴백(핸드오프 대기). **임의 기계번역 금지.**
- 데코용 목업 마이크로카피(가짜 파일명, ETA, MCP 툴 이름 등)는 번역 대상 아님 → 인라인 유지.

## 구조

```
landing/
  app/
    (en)/layout.tsx        # 영어 루트 레이아웃 (<html lang="en">, rootMetadata("en"))
    (en)/page.tsx          # 홈(en): <HomeBody lang="en"/> + pageMetadata
    (en)/blog|tools/...     # /blog, /blog/[slug], /tools, /tools/[slug]
    (ko)/layout.tsx        # 한국어 루트 레이아웃 (<html lang="ko">, rootMetadata("ko"))
    (ko)/ko/...            # /ko, /ko/blog, /ko/blog/[slug], /ko/tools, /ko/tools/[slug]
    _pages/HomeBody.tsx    # 홈 본문(로케일 공유)
    _sections/             # Hero…Footer, Nav, LangSwitch (모두 lang prop)
    _sections/faq-data.ts  # FaqItem 타입만(문항은 lib/i18n 사전)
    _seo/JsonLd.tsx        # <script type="application/ld+json"> 헬퍼
    blog/                  # _data.tsx, _components.tsx, BlogList.tsx, _index-body.tsx, _post-body.tsx
    tools/                 # _data.tsx, _components.tsx, panels/, lib/, _index-body.tsx, _slug-body.tsx
    sitemap.ts             # /sitemap.xml (en+ko, hreflang alternates)
    robots.ts              # /robots.txt (전체 허용 + AI 크롤러)
  lib/
    i18n/{en,ko,index}.ts  # 카피 사전 + getDict/Lang
    site.ts                # 전역 상수 + 로케일별 메타 + URL 헬퍼(localePath/absLocale/hreflangMap)
    metadata.ts            # rootMetadata(lang) / pageMetadata(lang, {...})
    schema.ts              # JSON-LD 빌더(lang 인자)
    asset.ts               # asset(path): 경로 그대로(하위호환, basePath 없음)
  public/                  # og.png, llms.txt, blog/ 이미지, demo/(정적, 영어 전용)
```

## 로케일 링크 규칙 (404/교차로케일 방지)
- 내부 링크는 `localePath(lang, path)`로 접두를 붙인다. 예: `localePath("ko","/blog/") → "/ko/blog/"`.
  `next/link`·`<a>` 모두 이 결과를 그대로 쓴다(배포가 루트라 이중 접두 문제 없음).
- 절대 URL(메타/사이트맵/OG/JSON-LD)은 `absLocale(lang, path)` / `abs()` / `absFromAsset()`.
- hreflang(en/ko/x-default)·canonical·og:locale은 `pageMetadata(lang, {path,...})`가 자동 생성.

## 새 블로그 글 추가 절차
1. `app/blog/_data.tsx`의 `POSTS`에 항목 추가(slug, 카테고리, 커버, 저자, 본문 FC).
2. 커버/피규어 이미지를 `public/blog/`에 넣고 `asset()`으로 참조.
3. `public/llms.txt`의 Blog 섹션에 링크 추가.
4. 빌드로 en/ko 라우트·사이트맵·JSON-LD·canonical 자동 반영 확인.

## SEO 배선
- 전역/로케일 상수: `lib/site.ts`. 메타 빌더: `lib/metadata.ts`. JSON-LD: `lib/schema.ts`.
- 페이지는 `pageMetadata(lang, {...})`로 canonical + hreflang + OG를 준다.
- Google Search Console 소유확인은 `site.ts`의 `googleSiteVerification` 토큰으로 자동 출력.

## 규칙
- **GitHub/오픈소스 노출 금지**(private 전환 예정). 방법론 링크는 내부 블로그로.
- 카피: sentence case, 느낌표/이모지/긴 대시(U+2014) 금지. 한국어는 임의 번역 금지(핸드오프).
- 핸드오프에 없는 섹션/카피를 임의 추가하기 전에 확인받는다.

## 검증
```bash
cd landing && pnpm exec next build   # Vercel과 동일. en/ko 라우트·sitemap·메타 생성 확인
```
빌드 후 `.next/server/app/index.html`(en), `ko.html`(ko)에서 `<html lang>`·canonical·hreflang 확인.
```

