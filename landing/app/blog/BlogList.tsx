"use client";
import * as React from "react";
import { PillTab, BlogCard, Button } from "@timbre/design-system";
import { asset } from "../../lib/asset";
import { CATEGORIES, type PostCard, type Category } from "./_data";

const INITIAL = 4;
const STEP = 3;

export function BlogList({ posts }: { posts: PostCard[] }) {
  const [cat, setCat] = React.useState<"All" | Category>("All");
  const [visible, setVisible] = React.useState(INITIAL);

  const filtered = React.useMemo(
    () => (cat === "All" ? posts : posts.filter((p) => p.category === cat)),
    [posts, cat]
  );
  const shown = filtered.slice(0, visible);

  return (
    <div>
      {/* category filter */}
      <div style={{ display: "flex", flexWrap: "wrap", gap: 4, marginBottom: 28 }}>
        {CATEGORIES.map((c) => (
          <PillTab
            key={c}
            active={cat === c}
            onClick={() => {
              setCat(c);
              setVisible(INITIAL);
            }}
          >
            {c}
          </PillTab>
        ))}
      </div>

      {/* 2-column card grid */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fill, minmax(360px, 1fr))",
          gap: 24,
        }}
      >
        {shown.map((p) => (
          <BlogCard
            key={p.slug}
            href={asset(`/blog/${p.slug}/`)}
            image={p.cover}
            category={p.category}
            title={p.title}
            excerpt={p.excerpt}
            author={p.authors[0]?.name}
            authorAvatar={p.authors[0]?.avatar}
            date={p.date}
            readTime={p.readTime}
          />
        ))}
      </div>

      {visible < filtered.length && (
        <div style={{ display: "flex", justifyContent: "center", marginTop: 40 }}>
          <Button variant="tertiary" onClick={() => setVisible((v) => v + STEP)}>
            Load more
          </Button>
        </div>
      )}
    </div>
  );
}
