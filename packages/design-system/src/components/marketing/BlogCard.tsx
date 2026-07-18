// Ported from source/components/cards/BlogCard.jsx — blog post card.
import * as React from "react";
import { Avatar } from "../shared/Avatar";
import { CategoryTag } from "./CategoryTag";

const FEAT = '"calt","kern","liga","ss03"';

export interface BlogCardProps
  extends Omit<React.AnchorHTMLAttributes<HTMLAnchorElement>, "title"> {
  image?: string;
  title?: React.ReactNode;
  excerpt?: React.ReactNode;
  author?: string;
  authorAvatar?: string;
  date?: string;
  /** optional category pill shown above the title */
  category?: string;
  /** optional read-time shown at the right of the meta row */
  readTime?: string;
}

export function BlogCard({
  image,
  title,
  excerpt,
  author,
  authorAvatar,
  date,
  category,
  readTime,
  href = "#",
  style,
  ...rest
}: BlogCardProps) {
  return (
    <a
      href={href}
      style={{
        display: "flex",
        flexDirection: "column",
        borderRadius: "var(--rc-radius-lg)",
        overflow: "hidden",
        background: "var(--rc-surface)",
        boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.1)",
        textDecoration: "none",
        ...style,
      }}
      {...rest}
    >
      <div
        style={{
          aspectRatio: "2.7 / 1",
          background: `center/cover no-repeat ${image ? `url(${image})` : "var(--rc-surface-elevated)"}`,
        }}
      />
      <div style={{ padding: 24, display: "flex", flexDirection: "column", gap: 12, flex: 1 }}>
        {category && (
          <div>
            <CategoryTag accent>{category}</CategoryTag>
          </div>
        )}
        <div style={{ font: "500 22px/1.25 var(--rc-font-sans)", fontFeatureSettings: FEAT, color: "var(--rc-ink)", whiteSpace: "pre-line" }}>
          {title}
        </div>
        {excerpt && (
          <div style={{ font: "400 15px/1.6 var(--rc-font-sans)", fontFeatureSettings: FEAT, color: "var(--rc-mute)", whiteSpace: "pre-line" }}>
            {excerpt}
          </div>
        )}
        <div style={{ marginTop: "auto", display: "flex", alignItems: "center", gap: 10, paddingTop: 8 }}>
          <Avatar src={authorAvatar} size={21} initials={author ? author[0] : undefined} />
          <span style={{ font: "400 13px/1.4 var(--rc-font-sans)", fontFeatureSettings: FEAT, color: "var(--rc-body)" }}>{author}</span>
          {date && <span style={{ font: "400 13px/1.4 var(--rc-font-sans)", fontFeatureSettings: FEAT, color: "var(--rc-stone)" }}>· {date}</span>}
          {readTime && (
            <span style={{ marginLeft: "auto", font: "400 13px/1.4 var(--rc-font-sans)", fontFeatureSettings: FEAT, color: "var(--rc-stone)" }}>
              {readTime}
            </span>
          )}
        </div>
      </div>
    </a>
  );
}
