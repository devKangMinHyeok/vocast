import type { MetadataRoute } from "next";
import { abs } from "../lib/site";

// output:"export" 에서 정적 /robots.txt 로 생성된다.
// 주의: GitHub Pages 프로젝트 경로(/vocast/)라 이 파일은 /vocast/robots.txt 에 놓인다.
// 크롤러는 보통 도메인 루트 robots만 읽으므로 참고용이며, 사이트맵은 Search Console에
// 직접 제출한다. 커스텀 도메인/루트 배포로 옮기면 그대로 유효해진다.
export const dynamic = "force-static";

// AI 검색/학습 크롤러 명시적 허용 (GEO: AI 답변에 인용될 수 있게)
const AI_BOTS = [
  "GPTBot",
  "ChatGPT-User",
  "OAI-SearchBot",
  "Google-Extended",
  "ClaudeBot",
  "Claude-Web",
  "anthropic-ai",
  "PerplexityBot",
  "Applebot-Extended",
  "cohere-ai",
];

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      { userAgent: "*", allow: "/" },
      ...AI_BOTS.map((ua) => ({ userAgent: ua, allow: "/" })),
    ],
    sitemap: abs("/sitemap.xml"),
  };
}
