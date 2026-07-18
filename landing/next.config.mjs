// Vocast 랜딩 — Next.js (App Router).
// - transpilePackages: 워크스페이스 DS(@timbre/design-system)의 raw TS/TSX를 Next가 컴파일.
// - GitHub Pages 배포(PAGES=1)일 때만 정적 export + /vocast basePath.
//   Vercel 등 루트 배포에서는 basePath 없이 그대로 동작.
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const isPages = process.env.PAGES === "1";
const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..");

/** @type {import('next').NextConfig} */
const nextConfig = {
  transpilePackages: ["@timbre/design-system"],
  images: { unoptimized: true },
  // public/ 정적 에셋(블로그 이미지 등)을 basePath 아래에서도 찾도록 노출.
  // 일반 <img>/CSS url()은 basePath가 자동 적용되지 않으므로 asset() 헬퍼로 접두.
  env: { NEXT_PUBLIC_BASE_PATH: isPages ? "/vocast" : "" },
  // 이 모노레포 루트를 트레이싱 루트로 고정 (상위 docusaurus-blog lockfile 오탐 방지)
  outputFileTracingRoot: repoRoot,
  ...(isPages
    ? { output: "export", basePath: "/vocast", trailingSlash: true }
    : {}),
};

export default nextConfig;
