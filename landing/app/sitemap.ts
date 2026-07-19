import type { MetadataRoute } from "next";
import { abs } from "../lib/site";
import { POSTS } from "./blog/_data";

// output:"export" 에서 정적 /sitemap.xml (→ /vocast/sitemap.xml)로 생성된다.
export const dynamic = "force-static";

export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date();

  const staticPages: MetadataRoute.Sitemap = [
    { url: abs("/"), lastModified: now, changeFrequency: "weekly", priority: 1 },
    { url: abs("/blog/"), lastModified: now, changeFrequency: "weekly", priority: 0.7 },
    { url: abs("/demo/"), lastModified: now, changeFrequency: "monthly", priority: 0.6 },
  ];

  const posts: MetadataRoute.Sitemap = POSTS.map((p) => ({
    url: abs(`/blog/${p.slug}/`),
    lastModified: new Date(p.date),
    changeFrequency: "monthly",
    priority: p.featured ? 0.8 : 0.6,
  }));

  return [...staticPages, ...posts];
}
