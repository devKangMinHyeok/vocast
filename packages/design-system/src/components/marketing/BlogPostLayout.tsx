// Ported from source/components/content/BlogPostLayout.jsx — article detail shell.
import * as React from "react";
import { Avatar } from "../shared/Avatar";
import { CategoryTag } from "./CategoryTag";
import type { BlogAuthor } from "./AuthorStack";

const FEAT = '"calt","kern","liga","ss03"';

export interface BlogPostLayoutProps
  extends Omit<React.HTMLAttributes<HTMLElement>, "title"> {
  category?: string;
  title?: React.ReactNode;
  description?: React.ReactNode;
  authors?: BlogAuthor[];
  date?: string;
  cover?: string;
  coverCaption?: React.ReactNode;
  backHref?: string;
  /** show the "← Blog" back link (default true) */
  showBack?: boolean;
  /** show the end-of-article author card (default false) */
  showAuthorFooter?: boolean;
  /** override the default author footer */
  footer?: React.ReactNode;
  maxWidth?: number;
}

export function BlogPostLayout({
  category,
  title,
  description,
  authors = [],
  date,
  cover,
  coverCaption,
  backHref = "#",
  showBack = true,
  children,
  footer,
  showAuthorFooter = false,
  maxWidth = 940,
  style,
  ...rest
}: BlogPostLayoutProps) {
  const names = authors.map((a) => a.name).filter(Boolean);
  return (
    <article style={{ maxWidth, margin: "0 auto", padding: "56px 24px 96px", ...style }} {...rest}>
      <header style={{ display: "flex", flexDirection: "column", alignItems: "flex-start", gap: 24 }}>
        {showBack && (
          <a href={backHref} style={{ font: "500 14px/1.4 var(--rc-font-sans)", letterSpacing: ".2px", fontFeatureSettings: FEAT, color: "var(--rc-mute)", textDecoration: "none" }}>
            ← Blog
          </a>
        )}
        {category && <CategoryTag accent>{category}</CategoryTag>}
        <h1 style={{ margin: 0, font: "600 clamp(38px,6vw,68px)/1.05 var(--rc-font-sans)", letterSpacing: "-.5px", fontFeatureSettings: FEAT, color: "var(--rc-ink)" }}>
          {title}
        </h1>
        {description && (
          <p style={{ margin: 0, maxWidth: 640, font: "400 21px/1.55 var(--rc-font-sans)", fontFeatureSettings: FEAT, color: "var(--rc-mute)" }}>{description}</p>
        )}
        {(names.length > 0 || date) && (
          <div style={{ marginTop: 8, width: "100%", display: "flex", alignItems: "center", justifyContent: "space-between", gap: 16, flexWrap: "wrap" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
              {authors.length > 0 && (
                <div style={{ display: "flex" }}>
                  {authors.slice(0, 4).map((a, i) => (
                    <Avatar key={i} src={a.avatar} initials={a.name ? a.name[0] : undefined} size={26} style={{ marginLeft: i ? -8 : 0, boxShadow: "0 0 0 2px var(--rc-canvas)" }} />
                  ))}
                </div>
              )}
              <span style={{ font: "500 13px/1.4 var(--rc-font-sans)", letterSpacing: "1px", textTransform: "uppercase", fontFeatureSettings: FEAT, color: "var(--rc-body)" }}>
                {names.join(", ")}
              </span>
            </div>
            {date && <span style={{ font: "400 13px/1.4 var(--rc-font-mono)", letterSpacing: "1px", textTransform: "uppercase", color: "var(--rc-mute)" }}>{date}</span>}
          </div>
        )}
      </header>

      <div style={{ margin: "32px 0 56px", borderTop: "1px solid var(--rc-hairline)" }} />

      {cover && (
        <figure style={{ margin: "0 0 56px" }}>
          <img src={cover} alt="" style={{ width: "100%", display: "block", borderRadius: "var(--rc-radius-xl)", background: "var(--rc-surface-elevated)" }} />
          {coverCaption && (
            <figcaption style={{ marginTop: 12, textAlign: "center", font: "italic 400 14px/1.5 var(--rc-font-sans)", fontFeatureSettings: FEAT, color: "var(--rc-mute)" }}>
              {coverCaption}
            </figcaption>
          )}
        </figure>
      )}

      {children}

      {(footer || (showAuthorFooter && authors.length > 0)) && (
        <div style={{ marginTop: 56, paddingTop: 32, borderTop: "1px solid var(--rc-hairline)", display: "flex", alignItems: "center", gap: 12 }}>
          {footer ?? (
            <>
              <div style={{ display: "flex" }}>
                {authors.slice(0, 4).map((a, i) => (
                  <Avatar key={i} src={a.avatar} initials={a.name ? a.name[0] : undefined} size={40} style={{ marginLeft: i ? -12 : 0, boxShadow: "0 0 0 2px var(--rc-canvas)" }} />
                ))}
              </div>
              <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
                <span style={{ font: "500 15px/1.3 var(--rc-font-sans)", letterSpacing: ".2px", fontFeatureSettings: FEAT, color: "var(--rc-ink)" }}>{names.join(", ")}</span>
                {date && <span style={{ font: "400 13px/1.4 var(--rc-font-sans)", fontFeatureSettings: FEAT, color: "var(--rc-mute)" }}>{date}</span>}
              </div>
            </>
          )}
        </div>
      )}
    </article>
  );
}
