import type { Metadata } from "next";
import { BlogFeatured } from "@timbre/design-system";
import { Nav } from "../_sections/Nav";
import { Footer } from "../_sections/Footer";
import { Container } from "../_ui/Container";
import { BlogList } from "./BlogList";
import { POSTS, postCards } from "./_data";
import { asset } from "../../lib/asset";

const FEAT = '"calt","kern","liga","ss03"';

export const metadata: Metadata = {
  title: "Blog — Vocast",
  description:
    "Notes on natural voice cloning, on-device audio, and shipping a voice you can actually publish. From the team building Vocast.",
};

export default function BlogIndex() {
  const featured = POSTS.find((p) => p.featured) ?? POSTS[0];
  const cards = postCards().filter((p) => !p.featured);

  return (
    <main>
      <Nav active="Blog" />
      <Container style={{ padding: "56px 24px 96px", maxWidth: 1180 }}>
        <header style={{ marginBottom: 48 }}>
          <h1 style={{ margin: 0, font: "600 clamp(38px,5vw,56px)/1.1 var(--rc-font-sans)", letterSpacing: "-.6px", fontFeatureSettings: FEAT, color: "var(--rc-ink)" }}>
            Blog
          </h1>
          <p style={{ margin: "16px 0 0", maxWidth: 560, font: "400 18px/1.6 var(--rc-font-sans)", fontFeatureSettings: FEAT, color: "var(--rc-mute)" }}>
            Notes on natural voice cloning, on-device audio, and shipping a voice you can actually
            publish.
          </p>
        </header>

        <BlogFeatured
          image={featured.cover}
          category={featured.category}
          title={featured.title}
          excerpt={featured.excerpt}
          authors={featured.authors}
          date={featured.date}
          href={asset(`/blog/${featured.slug}/`)}
          style={{ marginBottom: 56 }}
        />

        <div style={{ borderTop: "1px solid var(--rc-hairline)", paddingTop: 48 }}>
          <BlogList posts={cards} />
        </div>
      </Container>
      <Footer />
    </main>
  );
}
