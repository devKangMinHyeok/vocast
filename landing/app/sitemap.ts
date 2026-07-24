import type { MetadataRoute } from "next";
import { abs, absLocale } from "../lib/site";
import { LANGS } from "../lib/i18n";
import { POSTS } from "./blog/_data";
import { liveTools } from "./tools/_data";

// Vercel 루트 배포에서 /sitemap.xml 로 생성된다.
export const dynamic = "force-static";

// 언어 무관 경로 하나 → en/ko 두 엔트리(+ 상호 hreflang alternates).
function bilingual(
  path: string,
  opts: { changeFrequency: MetadataRoute.Sitemap[number]["changeFrequency"]; priority: number; lastModified?: Date },
): MetadataRoute.Sitemap {
  const languages = Object.fromEntries(LANGS.map((l) => [l, absLocale(l, path)]));
  return LANGS.map((l) => ({
    url: absLocale(l, path),
    lastModified: opts.lastModified ?? new Date(),
    changeFrequency: opts.changeFrequency,
    priority: opts.priority,
    alternates: { languages },
  }));
}

export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date();

  const staticPages: MetadataRoute.Sitemap = [
    ...bilingual("/", { changeFrequency: "weekly", priority: 1 }),
    ...bilingual("/blog/", { changeFrequency: "weekly", priority: 0.7 }),
    ...bilingual("/tools/", { changeFrequency: "weekly", priority: 0.8 }),
    ...bilingual("/compare/", { changeFrequency: "monthly", priority: 0.7 }),
    // /demo/ 는 public/ 정적 데모(영어 전용). 로케일 대안 없음.
    { url: abs("/demo/"), lastModified: now, changeFrequency: "monthly", priority: 0.6 },
  ];

  const tools: MetadataRoute.Sitemap = liveTools().flatMap((t) =>
    bilingual(`/tools/${t.slug}/`, { changeFrequency: "monthly", priority: 0.7 }),
  );

  const posts: MetadataRoute.Sitemap = POSTS.flatMap((p) =>
    bilingual(`/blog/${p.slug}/`, {
      changeFrequency: "monthly",
      priority: p.featured ? 0.8 : 0.6,
      lastModified: new Date(p.date),
    }),
  );

  return [...staticPages, ...tools, ...posts];
}
