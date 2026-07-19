// 사이트 전역 SEO/메타 단일 소스.
// layout(메타태그), sitemap, robots, JSON-LD가 모두 이 상수를 참조한다.
// (edgelink-landing의 site-metadata.ts 패턴을 우리 구조에 맞게 이식)

export const SITE = {
  name: "Vocast",
  // 검색결과 타이틀/OG에 쓰는 짧은 태그라인
  tagline: "read any script in your own voice",
  description:
    "Vocast is a local, on-device Mac voice studio for creators. Clone your voice from about ninety seconds of audio, then narrate scripts up to 20,000 characters in a voice that sounds like you. Fully local, no account, no subscription. $49 one-time.",

  // GitHub Pages 프로젝트 경로: origin + basePath 로 분리해 절대 URL을 정확히 조립한다.
  origin: "https://devkangminhyeok.github.io",
  basePath: "/vocast",

  locale: "en_US",
  lang: "en",

  ogImage: "/og.png", // public/og.png (1200x630)
  twitter: "", // @핸들 생기면 채우기 (예: "@vocast")
  github: "https://github.com/devKangMinHyeok/vocast",

  price: { amount: "49", currency: "USD" },
  author: { name: "Minhyeok Kang", url: "https://github.com/devKangMinHyeok" },

  keywords: [
    "voice cloning",
    "AI voice",
    "text to speech",
    "on-device voice",
    "local voice studio",
    "Mac voice app",
    "narration",
    "voiceover",
    "audiobook narration",
    "MCP",
    "Apple Silicon",
    "voice generator",
    "noise removal",
  ],

  // Google Search Console 소유확인(메타태그 방식). 발급 토큰을 넣으면 자동으로 <meta> 출력.
  googleSiteVerification: "",
} as const;

/** 사이트 정식 루트 URL (끝 슬래시 없음): https://devkangminhyeok.github.io/vocast */
export const SITE_URL = `${SITE.origin}${SITE.basePath}`;

/** basePath 없는 라우트/공개파일 경로 → 절대 URL. 예: abs("/blog/") */
export function abs(path: string): string {
  return `${SITE_URL}${path.startsWith("/") ? path : `/${path}`}`;
}

/** 이미 basePath가 붙은 asset() 결과 → 절대 URL. 예: absFromAsset("/vocast/blog/x.png") */
export function absFromAsset(assetPath: string): string {
  return `${SITE.origin}${assetPath}`;
}
