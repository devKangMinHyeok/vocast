// Ported from source/components/content/BlogFeatured.jsx — full-width index lead post.
import * as React from "react";
import { AuthorStack, type BlogAuthor } from "./AuthorStack";
import { CategoryTag } from "./CategoryTag";

const FEAT = '"calt","kern","liga","ss03"';

export interface BlogFeaturedProps
  extends Omit<React.AnchorHTMLAttributes<HTMLAnchorElement>, "title"> {
  image?: string;
  category?: string;
  title?: React.ReactNode;
  excerpt?: React.ReactNode;
  authors?: BlogAuthor[];
  date?: string;
  href?: string;
  /** image on the right instead of the left */
  flip?: boolean;
}

export function BlogFeatured({
  image,
  category,
  title,
  excerpt,
  authors = [],
  date,
  href = "#",
  flip = false,
  style,
  ...rest
}: BlogFeaturedProps) {
  const media = (
    <div style={{ flex: "1 1 0", minWidth: 0, alignSelf: "stretch", borderRadius: "var(--rc-radius-lg)", overflow: "hidden", background: "var(--rc-surface-elevated)" }}>
      <div
        style={{
          width: "100%",
          height: "100%",
          minHeight: 300,
          background: `center/cover no-repeat ${image ? `url(${image})` : "var(--rc-surface-elevated)"}`,
        }}
      />
    </div>
  );
  const body = (
    <div style={{ flex: "1 1 0", minWidth: 0, display: "flex", flexDirection: "column", justifyContent: "center", gap: 20, padding: "8px 8px 8px 0" }}>
      {category && (
        <div>
          <CategoryTag accent>{category}</CategoryTag>
        </div>
      )}
      <h2 style={{ margin: 0, font: "600 40px/1.12 var(--rc-font-sans)", letterSpacing: ".2px", fontFeatureSettings: FEAT, color: "var(--rc-ink)" }}>
        {title}
      </h2>
      {excerpt && (
        <p style={{ margin: 0, font: "400 18px/1.6 var(--rc-font-sans)", fontFeatureSettings: FEAT, color: "var(--rc-body)" }}>{excerpt}</p>
      )}
      {authors.length > 0 && <AuthorStack authors={authors} date={date} />}
    </div>
  );
  return (
    <a href={href} style={{ display: "flex", gap: 40, alignItems: "stretch", textDecoration: "none", flexWrap: "wrap", ...style }} {...rest}>
      {flip ? (
        <>
          {body}
          {media}
        </>
      ) : (
        <>
          {media}
          {body}
        </>
      )}
    </a>
  );
}
