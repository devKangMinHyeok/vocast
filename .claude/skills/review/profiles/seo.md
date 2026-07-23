# SEO Audit Profile

Vocast 랜딩(이중언어 EN/KO, Next.js App Router, Vercel 루트 배포 vocast.me)의 Technical +
On-Page SEO와 구조화 데이터를 감사한다. 영어는 루트(`/`), 한국어는 `/ko/`.

**핵심 질문**: "검색엔진이 이 페이지를 정확히 크롤링/이해/색인할 기술 기반을 갖췄는가?"

## 파일 필터
- `landing/app/**/page.tsx`, `landing/app/(en)/layout.tsx`, `landing/app/(ko)/layout.tsx`
- `landing/app/sitemap.ts`, `landing/app/robots.ts`
- `landing/lib/site.ts`, `landing/lib/metadata.ts`, `landing/lib/schema.ts`

## 체크리스트

### A. 렌더링/색인
- [ ] 모든 공개 라우트가 프리렌더되는가? (JS 없이 콘텐츠 보임)
- [ ] 새 라우트가 en/ko 두 로케일로 `app/sitemap.ts`에 포함되는가? 절대 URL + hreflang alternates?
- [ ] `robots.ts`가 전체 허용 + `Sitemap:`(https://vocast.me/sitemap.xml) + AI 크롤러 허용을 갖는가?

### B. Canonical / hreflang / 메타
- [ ] 모든 페이지에 self-referencing 절대 canonical이 있는가? (`absLocale(lang, path)` 사용)
- [ ] hreflang이 en/ko/x-default로 상호 링크되는가? (`pageMetadata`의 `alternates.languages`)
- [ ] `<html lang>`이 로케일별로(en/ko) 정확한가? og:locale + og:locale:alternate 완비?
- [ ] `<title>` 존재/고유/길이(대략 45~65자)? description 존재/고유(대략 80~160자)?
- [ ] OpenGraph(type/title/description/url/image 1200x630/siteName/locale) 완비?
- [ ] `twitter:card = summary_large_image`?
- [ ] 페이지별 title/description 중복이 없는가?

### C. 구조화 데이터 (JSON-LD)
- [ ] 홈: Organization + WebSite + SoftwareApplication(가격/OS/카테고리) + FAQPage
- [ ] 블로그 글: BlogPosting(headline/image/datePublished/author Person/publisher) + BreadcrumbList
- [ ] 값이 실제와 일치하는가? 없는 데이터(리뷰 평점 등)를 지어내지 않았는가?
- [ ] 전부 `lib/schema.ts`를 통하는가?

### D. 콘텐츠 구조
- [ ] 페이지당 H1 1개, 계층 건너뜀 없음, H1에 핵심 키워드?
- [ ] 이미지 `alt` 존재, 크기 지정(레이아웃 시프트 예방)?
- [ ] URL 소문자 + 하이픈, `trailingSlash` 일관?

### E. Core Web Vitals (코드 추정)
- [ ] above-the-fold 이미지에 lazy 미적용/우선 로드? below-the-fold는 lazy?
- [ ] 크기 미지정 요소로 인한 CLS 위험 없는가?
- [ ] 폰트 로드 전략(swap/optional) 적용?

## 요약 출력
카테고리(Technical / On-Page / 구조화 데이터)별 점수 + P0/P1/P2 액션 플랜.

## 주의
- 영어/글로벌 타깃. `<html lang="en">` 유지. Naver/한국 SEO 항목은 적용하지 않는다.
- 코드 분석 기반이며 실제 크롤 결과는 Search Console/Rich Results Test로 확인.
