import type { Metadata, Viewport } from "next";
// Design system tokens + fonts + body defaults (dark canvas, Inter ss03).
import "@timbre/design-system/styles.css";
import "./globals.css";
import { SITE, SITE_URL, abs } from "../lib/site";

const TITLE = `${SITE.name}, ${SITE.tagline}`;

export const metadata: Metadata = {
  metadataBase: new URL(`${SITE_URL}/`),
  title: {
    default: TITLE,
    template: `%s · ${SITE.name}`,
  },
  description: SITE.description,
  applicationName: SITE.name,
  keywords: [...SITE.keywords],
  authors: [{ name: SITE.author.name, url: SITE.author.url }],
  creator: SITE.author.name,
  publisher: SITE.name,
  category: "technology",
  alternates: { canonical: abs("/") },
  openGraph: {
    type: "website",
    siteName: SITE.name,
    title: TITLE,
    description: SITE.description,
    url: abs("/"),
    locale: SITE.locale,
    images: [{ url: abs(SITE.ogImage), width: 1200, height: 630, alt: `${SITE.name}, on-device voice studio` }],
  },
  twitter: {
    card: "summary_large_image",
    title: TITLE,
    description: SITE.description,
    images: [abs(SITE.ogImage)],
    ...(SITE.twitter ? { site: SITE.twitter, creator: SITE.twitter } : {}),
  },
  robots: {
    index: true,
    follow: true,
    googleBot: { index: true, follow: true, "max-image-preview": "large", "max-snippet": -1 },
  },
  icons: {
    icon: abs("/blog/vocast-mark.svg"),
  },
  ...(SITE.googleSiteVerification
    ? { verification: { google: SITE.googleSiteVerification } }
    : {}),
};

export const viewport: Viewport = {
  themeColor: "#07080a",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang={SITE.lang}>
      <body>{children}</body>
    </html>
  );
}
