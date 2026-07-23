# Vocast (denoise-app)

로컬 온디바이스 맥 음성 스튜디오. 보이스 클로닝 + 노이즈 제거. 제품명은 **Vocast**
(로컬 폴더명은 `denoise-app`, GitHub 저장소는 `vocast`). 1인 개발 + 유튜브 데모 맥락이라
**코딩 초보자 관점으로 쉽게 설명**하고, 되돌리기 어려운 큰 변경 전에는 계획을 먼저 보여주고
확인받는다. 말로만 "다 했다"가 아니라 실제로 빌드/실행해 결과를 보여준다.

## 저장소 구성 (pnpm workspace + Python)

| 경로 | 내용 |
|------|------|
| `landing/` | Next.js(App Router) 마케팅 랜딩 + 블로그. Vercel + vocast.me 정식 배포 |
| `packages/design-system/` | `@timbre/design-system` (Timbre DS). React + TS, `--rc-*` CSS 토큰, Storybook |
| `packages/voxa/` | 파이썬 음성 엔진 (media/denoise/clone/analysis) |
| `app/` | 로컬 앱(파이썬 CLI/웹) + 맥 앱 |
| `packaging/` | 맥 앱/번들 빌드 |
| `docs/` | 품질 방법론 등 문서 |
| `.github/workflows/` | `ci.yml`(유닛), `quality.yml`(품질 게이트), `pages.yml`(Storybook만 Pages 배포) |

- 패키지 매니저: **pnpm 10.22.0**. JS 워크스페이스는 `landing` + `packages/design-system`.
  (voxa는 파이썬이라 JS 워크스페이스에 없음.)
- 정식 배포: **Vercel + 커스텀 도메인 vocast.me** (`main` 푸시 시 자동 배포, 루트 서빙).
  GitHub Pages는 Storybook만 (`devkangminhyeok.github.io/vocast/`).
  (도메인 붙이기 전까지 vocast.me DNS 작업은 `polaris/specs/planned/`에 spec으로 있음.)

## 표준 규칙 (반드시 지킬 것)

1. **긴 대시 구분자 금지**: 유니코드 U+2014(em dash)와 U+2015를 응답과 생성 콘텐츠/코드/예제
   어디에도 쓰지 않는다. 쉼표/콜론/마침표/괄호로 바꾸거나 문장을 다시 쓴다.
   (자동 차단 훅: `.claude/hooks/guard-no-emdash.py`, Write/Edit/MultiEdit에서 deny.)
2. **랜딩 카피**: 영어 우선 + 한국어 지원(이중언어). sentence case, 느낌표와 이모지 금지.
   마케팅 과장 대신 사실과 수치. 용어 일관성(Vocast, on-device, one-time, voice cloning).
   카피는 `landing/lib/i18n/{en,ko}.ts` 사전에서 온다(섹션에 하드코딩 금지).
   **한국어는 임의 기계번역하지 않는다**: 디자인 핸드오프로 채우기 전까지 영어로 폴백한다.
3. **디자인(Timbre DS)**: 색/타입/여백/라운드는 DS 토큰(`--rc-*`)에서만 가져온다. 다크 전용.
   카드는 hairline 보더 + 그림자 없음. 버튼 채움색은 흰색만. 브랜드 오렌지(#f5732b)는 워드마크
   마침표, 강조 단어, 지표 마크에만. 새 색/폰트/간격을 도입하지 않는다. 자세히는 `/timbre-design`.
4. **이중언어 라우팅 / 링크**:
   - 라우트 그룹 `app/(en)/`(루트) + `app/(ko)/ko/`가 각자 루트 레이아웃을 가져
     `<html lang>`이 로케일별로 나온다. 영어는 루트(`/`), 한국어는 `/ko/`. 페이지 본문은
     `app/_pages`·`app/blog/_*-body.tsx`·`app/tools/_*-body.tsx` 공유 컴포넌트를 lang만 바꿔 재사용.
   - 내부 링크는 `lib/site.ts`의 `localePath(lang, path)`로 로케일 접두를 붙인다.
     절대 URL(메타/사이트맵/OG)은 `absLocale(lang, path)` / `abs()` / `absFromAsset()`.
   - hreflang(en/ko/x-default)·canonical·og:locale은 `lib/metadata.ts`의
     `pageMetadata(lang, {...})`가 만든다. 루트 레이아웃 기본 메타는 `rootMetadata(lang)`.
   - 배포는 Vercel 루트(basePath 없음). `asset()`은 이제 경로를 그대로 돌려주는 하위호환 헬퍼.
   - Server Component 기본. 이벤트 핸들러/상태가 필요한 컴포넌트만 `"use client"`.
5. **GitHub 노출 금지**: 유료 출시 후 저장소를 private로 전환 예정. 랜딩/블로그/구조화 데이터에
   GitHub 링크나 "오픈소스" 문구를 넣지 않는다.
6. **작업 흐름**: landing 변경 시 `cd landing && pnpm exec next build`로 검증한 뒤 (Vercel과 동일)
   커밋한다. **커밋/푸시는 사용자가 요청할 때만.** main에서 작업 중이면 상관없지만 커밋 메시지
   끝에는 `Co-Authored-By` 라인을 남긴다.
7. **SEO 단일 소스**: 사이트 전역 상수는 `landing/lib/site.ts`(로케일별 tagline/description/
   keywords 포함), 메타 빌더는 `lib/metadata.ts`, JSON-LD 빌더는 `lib/schema.ts`(둘 다 lang
   인자를 받음). sitemap/robots/페이지 메타가 모두 이걸 참조한다. 블로그 글을 추가/수정하면
   `landing/public/llms.txt`도 갱신한다. 감사는 `/review seo`, `/review geo`.
8. **맥 앱은 항상 베타로 빌드**: 출시 전까지 프로덕션(release) 빌드를 뽑지 않는다. 기본은
   `make beta`(= `bash apps/mac/build_app.sh`)이고, 시안 아이콘의 "Vocast Beta"가 나온다.
   프로덕션은 **사용자가 "출시"를 명시적으로 지시할 때만**. 릴리스는 `VOCAST_RELEASE_CONFIRM=yes`
   와 `VOCAST_SIGN_ID`가 둘 다 있어야 실행되고(스크립트 가드), Bash 훅
   (`.claude/hooks/guard-release-build.py`)이 시도를 사용자에게 확인받는다.
   Swift만 고쳤다면 `make quick`(엔진 재사용, 약 1분). 파이썬을 건드렸다면 쓰지 않는다.
   의존성을 덜어낸 뒤에는 4개 플로우(health, denoise, 프로필 빌드, non-fast 내레이션)를
   전부 돌려 확인한다. 지연 임포트 때문에 일부만 통과하는 일이 실제로 있었다.

## 작업 → 스킬 매핑

| 작업 | 스킬 |
|------|------|
| 변경분 전문가 리뷰 | `/review [code\|design\|copy\|seo\|geo]` |
| 랜딩 구조/섹션/라우팅/블로그 | `/landing` |
| Timbre DS 컴포넌트/토큰/스타일 | `/timbre-design` |
| SEO 메타/구조화 데이터/사이트맵 | `/review seo` (+ `landing/lib/site.ts`) |
| AI 검색(GEO) 최적화 | `/review geo` (+ `landing/public/llms.txt`) |

스킬은 `.claude/skills/`에 있다.

<!-- POLARIS-START (do not edit between markers; managed by Polaris) -->
## Polaris

This repository uses [Polaris](https://github.com/retemper/polaris) — strategy-as-code for AI agents. The rules below govern your behavior in this repository.

**Before proposing any non-trivial code change:**
- Read `polaris/mission.md`. Internalize the anti-strategy items, the current phase, and the riskiest strategic assumption.
- Read `polaris/philosophy.md` if present. These principles are invariant across Goal changes — every proposal must respect them.
- List `polaris/goals/active/` and read the frontmatter of each active Goal. These are the outcomes the repo is currently converging on.
- Scan `polaris/specs/in-progress/` and `polaris/specs/planned/` for a Spec that covers the proposed work.

**When no Spec covers the proposed work:**
- Run `/spec` to create one. Do not write implementation code until the Spec exists on disk.
- One-line fixes and obvious chores can bypass Spec creation, but you must say so explicitly in chat before acting.

**When the user reports a bug, incident, or observation that isn't itself a Spec-scoped change:**
- Run `/issue` to file it under `polaris/issues/open/`. Issues are lightweight operational reports, not strategic layers — no Clarity Gate scoring applies.
- When a later Spec addresses the Issue, `/spec` records the link on the Spec side via `related_issues:`. The Issue file does not store its Spec.

**When a Spec exists for this work:**
- Stay within the scope declared in S1 (what changes) and S3 (out of scope).
- The Spec's `goal:` frontmatter field names its parent Goal in `polaris/goals/active/`. Verify the work still advances that Goal's G1 target outcome — if it drifts, raise it.
- If the Spec's `related_issues:` lists any Issues, they live in `polaris/issues/open/`. Resolving the Spec closes those Issues (`git mv` to `polaris/issues/closed/` and fill `Resolution notes`).
- If the work requires expanding scope, stop and ask the user to amend the Spec.

**When the proposed work spans multiple Specs (umbrella effort):**
- Each piece is its own Spec under the umbrella's group folder. Hierarchy is filesystem-only: the parent's full slug is a folder under `polaris/specs/{status}/`; the parent file is `{parent-slug}/{parent-slug}.md`; children live as sibling files inside.
- Children's statuses diverge freely from the parent's — the same group folder appears under multiple status dirs (e.g., `polaris/specs/in-progress/{parent-slug}/` for in-flight pieces, `polaris/specs/done/{parent-slug}/` for completed pieces).
- To find every Spec in a group: `find polaris/specs -path "*/{parent-slug}/*"`.
- To attach a Spec to a parent or change its parent: `git mv` only. There is no `parent_spec:` frontmatter field — `/spec` asks "Is this Spec part of a larger Spec?" during creation, and any later restructuring is a manual `git mv`.

**When the user expresses disorientation or asks an open-ended navigation question:**
- Signal examples: "what should I do next", "where are we", "what's in progress", "뭐 해야지", "지금 뭐가 필요해", "어디까지 했지".
- Suggest `/polaris` — it reads current filesystem state and proposes concrete next moves. Do not improvise an answer from memory of the codebase state.

**If the proposed change conflicts with an anti-strategy item in `polaris/mission.md` or a principle in `polaris/philosophy.md`:**
- Halt. Name the specific item or principle being violated and raise the conflict with the user.
- Do not silently proceed. The user must either cancel the change or explicitly amend the conflicting file.

**Never:**
- Trust metadata over filesystem reality. The directory a Spec, Goal, or Issue lives in IS its status — `planned/` `in-progress/` `done/` `canceled/` for Specs, `active/` `achieved/` `abandoned/` for Goals, `open/` `closed/` for Issues. No `status:` field overrides this.
- Move Spec, Goal, or Issue files across status directories, or rewrite `polaris/mission.md` or `polaris/philosophy.md`, without the user's explicit request.
- Create a Spec without a parent Goal. Every Spec must link to an active Goal via its `goal:` frontmatter field.
- Treat Philosophy principles as aspirational. If a principle exists in `polaris/philosophy.md`, violating it is a strategic decision that requires explicit user amendment, not silent deviation.
- Store Spec references on Issues. The Spec's `related_issues:` frontmatter is the canonical direction for the Spec↔Issue link. Issues do not carry a `related_specs:` field.
- Add a `parent_spec:`, `children:`, or any similar field to record Spec hierarchy. The folder structure under `polaris/specs/{status}/{parent-slug}/` is canonical; `git mv` is the only attach/detach/reparent mechanism.

**Directory layout (strategic context):**
- `polaris/mission.md` — mission, anti-strategy, current phase, riskiest strategic assumption
- `polaris/philosophy.md` — principles invariant across Goal changes (identity-level commitments); may not exist if the user hasn't defined any
- `polaris/goals/active/` — outcomes currently being pursued
- `polaris/goals/achieved/` — outcomes that have been observed (historical reference; `Outcome notes` section filled)
- `polaris/goals/abandoned/` — outcomes no longer being pursued, with reason recorded
- `polaris/specs/planned/` — Specs not yet started
- `polaris/specs/in-progress/` — active work
- `polaris/specs/done/` — completed (historical reference)
- `polaris/specs/canceled/` — canceled with reason recorded in the Spec
- `polaris/specs/{status}/{parent-slug}/` — when a Spec has children, it becomes a group folder under its status dir. Parent file: `{parent-slug}/{parent-slug}.md`. Children: sibling files in the same folder. Each Spec's status is independent, so the same group folder may appear under multiple status dirs.
- `polaris/issues/open/` — bug / incident / observation reports not yet resolved
- `polaris/issues/closed/` — resolved, wontfix, duplicate, or obsolete Issues with `Resolution notes` filled

**Slash commands (from the Polaris plugin):**
- `/init` — one-time setup: interview for mission, anti-strategy, phase, philosophy, and 2-3 initial Goals
- `/philosophy` — add a new Philosophy principle (P1–P3 interrogation)
- `/goal` — add a new Goal (G1–G4 interrogation)
- `/spec` — create a new Spec under a parent Goal (Clarity Gate S1–S6)
- `/issue` — file a bug / incident / observation report (structural, no scoring)
- `/polaris` — compass: read current state and propose next moves (use when disoriented; accepts optional context arg)
<!-- POLARIS-END -->
