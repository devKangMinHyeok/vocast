import { Nav } from "./_sections/Nav";
import { Hero } from "./_sections/Hero";
import { Problem } from "./_sections/Problem";
import { Features } from "./_sections/Features";
import { Quality } from "./_sections/Quality";
import { LocalFirst } from "./_sections/LocalFirst";
import { Mcp } from "./_sections/Mcp";
import { Pricing } from "./_sections/Pricing";
import { Faq } from "./_sections/Faq";
import { FinalCta } from "./_sections/FinalCta";
import { Footer } from "./_sections/Footer";
import { FAQ_ITEMS } from "./_sections/faq-data";
import { JsonLd } from "./_seo/JsonLd";
import {
  graph,
  organizationSchema,
  websiteSchema,
  softwareApplicationSchema,
  faqPageSchema,
} from "../lib/schema";

// Single-route Vocast landing, composed from section components built on the
// Timbre design system (tokens + primitives). Almost entirely static; only Nav,
// HeroPlayer, KaraokeDemo and Faq are client components.
export default function Page() {
  return (
    <main>
      <JsonLd
        data={graph(
          organizationSchema(),
          websiteSchema(),
          softwareApplicationSchema(),
          faqPageSchema(FAQ_ITEMS),
        )}
      />
      <Nav />
      <Hero />
      <Problem />
      <Features />
      <Quality />
      <LocalFirst />
      <Mcp />
      <Pricing />
      <Faq />
      <FinalCta />
      <Footer />
    </main>
  );
}
