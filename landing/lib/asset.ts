// Prefix a public/ asset path with the deploy basePath (e.g. /vocast on GitHub Pages,
// empty on Vercel / local dev). Use for plain <img>/CSS url() where Next doesn't
// auto-apply basePath. next/link and route hrefs already handle basePath themselves.
const BASE = process.env.NEXT_PUBLIC_BASE_PATH || "";

export function asset(path: string): string {
  return `${BASE}${path.startsWith("/") ? path : `/${path}`}`;
}
