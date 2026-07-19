import type { Metadata } from "next";
import { Nav } from "../_sections/Nav";
import { Footer } from "../_sections/Footer";
import { BlogHeader, FeaturedPost } from "./_components";
import { BlogList } from "./BlogList";
import { postCards } from "./_data";
import { JsonLd } from "../_seo/JsonLd";
import { abs } from "../../lib/site";
import { graph, breadcrumbSchema } from "../../lib/schema";

const DESCRIPTION =
  "How we build voice cloning and narration that you can measure. Methodology, metrics, local-first engineering, and product notes.";

export const metadata: Metadata = {
  title: "The Vocast blog",
  description: DESCRIPTION,
  alternates: { canonical: abs("/blog/") },
  openGraph: {
    type: "website",
    url: abs("/blog/"),
    title: "The Vocast blog",
    description: DESCRIPTION,
  },
};

export default function BlogIndex() {
  const cards = postCards();
  const featured = cards.find((p) => p.featured) ?? cards[0];
  const rest = cards.filter((p) => !p.featured);

  return (
    <main>
      <JsonLd
        data={graph(
          breadcrumbSchema([
            { name: "Home", path: "/" },
            { name: "Blog", path: "/blog/" },
          ]),
        )}
      />
      <Nav active="Blog" />
      <div style={{ maxWidth: 1080, margin: "0 auto", padding: "56px 24px 96px" }}>
        <BlogHeader />
        <div style={{ marginBottom: 56 }}>
          <FeaturedPost post={featured} />
        </div>
        <BlogList posts={rest} />
      </div>
      <Footer />
    </main>
  );
}
