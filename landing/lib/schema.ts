// schema.org JSON-LD 빌더. 홈/블로그 페이지가 이 객체를 <JsonLd>로 심는다.
// 수치/사실만 사용하고, 리뷰 평점 등 없는 데이터는 만들지 않는다.
import { SITE, SITE_URL, abs, absFromAsset } from "./site";
import type { FaqItem } from "../app/_sections/faq-data";

const ORG_ID = `${SITE_URL}/#organization`;
const SITE_ID = `${SITE_URL}/#website`;
const APP_ID = `${SITE_URL}/#app`;

/** "Jul 19, 2026" → "2026-07-19" (ISO date, 스키마 date 필드용) */
function isoDate(human: string): string {
  const d = new Date(human);
  return Number.isNaN(d.getTime()) ? human : d.toISOString().slice(0, 10);
}

export function organizationSchema() {
  return {
    "@type": "Organization",
    "@id": ORG_ID,
    name: SITE.name,
    url: abs("/"),
    logo: abs("/blog/vocast-mark.svg"),
    sameAs: [SITE.github],
  };
}

export function websiteSchema() {
  return {
    "@type": "WebSite",
    "@id": SITE_ID,
    name: SITE.name,
    url: abs("/"),
    inLanguage: SITE.lang,
    publisher: { "@id": ORG_ID },
  };
}

/** 제품 자체(맥 앱) 스키마. 가격/OS/카테고리 등 factual 정보만. */
export function softwareApplicationSchema() {
  return {
    "@type": "SoftwareApplication",
    "@id": APP_ID,
    name: SITE.name,
    description: SITE.description,
    url: abs("/"),
    applicationCategory: "MultimediaApplication",
    operatingSystem: "macOS 12+ (Apple Silicon)",
    offers: {
      "@type": "Offer",
      price: SITE.price.amount,
      priceCurrency: SITE.price.currency,
      category: "one-time purchase",
    },
    publisher: { "@id": ORG_ID },
    inLanguage: SITE.lang,
  };
}

export function faqPageSchema(items: FaqItem[]) {
  return {
    "@type": "FAQPage",
    mainEntity: items.map((it) => ({
      "@type": "Question",
      name: it.q,
      acceptedAnswer: { "@type": "Answer", text: it.a },
    })),
  };
}

export interface ArticleInput {
  slug: string;
  title: string;
  excerpt: string;
  cover: string; // asset()로 basePath가 붙은 경로
  date: string;
  authors: { name: string; url?: string; avatar?: string; role?: string }[];
}

export function articleSchema(post: ArticleInput) {
  const url = abs(`/blog/${post.slug}/`);
  return {
    "@type": "BlogPosting",
    headline: post.title,
    description: post.excerpt,
    image: absFromAsset(post.cover),
    datePublished: isoDate(post.date),
    dateModified: isoDate(post.date),
    inLanguage: SITE.lang,
    url,
    mainEntityOfPage: url,
    author: post.authors.map((a) => ({
      "@type": "Person",
      name: a.name,
      ...(a.role ? { jobTitle: a.role } : {}),
      ...(a.url ? { url: a.url } : {}),
      ...(a.avatar ? { image: absFromAsset(a.avatar) } : {}),
    })),
    publisher: { "@id": ORG_ID },
  };
}

/** items: [{ name, path(basePath 없는 경로) }] 순서대로 위치 부여 */
export function breadcrumbSchema(items: { name: string; path: string }[]) {
  return {
    "@type": "BreadcrumbList",
    itemListElement: items.map((it, i) => ({
      "@type": "ListItem",
      position: i + 1,
      name: it.name,
      item: abs(it.path),
    })),
  };
}

/** 여러 스키마를 하나의 @graph 로 묶어 반환 */
export function graph(...nodes: object[]) {
  return { "@context": "https://schema.org", "@graph": nodes };
}
