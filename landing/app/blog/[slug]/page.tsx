import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { BlogPostLayout } from "@timbre/design-system";
import { Nav } from "../../_sections/Nav";
import { Footer } from "../../_sections/Footer";
import { StripeBand } from "../../_ui/StripeBand";
import { POSTS, getPost } from "../_data";
import { asset } from "../../../lib/asset";

// Static export needs every slug up front.
export function generateStaticParams() {
  return POSTS.map((p) => ({ slug: p.slug }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const post = getPost(slug);
  if (!post) return { title: "Blog — Vocast" };
  return {
    title: `${post.title} — Vocast`,
    description: post.excerpt,
  };
}

export default async function BlogPostPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const post = getPost(slug);
  if (!post) notFound();
  const Body = post.Body;

  return (
    <main>
      <Nav active="Blog" />
      <BlogPostLayout
        category={post.category}
        title={post.title}
        description={post.excerpt}
        authors={post.authors}
        date={post.date}
        cover={post.cover}
        backHref={asset("/blog/")}
        showAuthorFooter
      >
        <Body />
      </BlogPostLayout>
      <StripeBand />
      <Footer />
    </main>
  );
}
