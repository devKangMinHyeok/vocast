// Ported from source/components/content/AuthorStack.jsx — co-author avatar cluster.
import * as React from "react";
import { Avatar } from "../shared/Avatar";

const FEAT = '"calt","kern","liga","ss03"';

export interface BlogAuthor {
  name: string;
  avatar?: string;
}

export interface AuthorStackProps extends React.HTMLAttributes<HTMLDivElement> {
  /** one or more co-authors (up to 4 avatars shown) */
  authors?: BlogAuthor[];
  date?: string;
  size?: number;
}

export function AuthorStack({
  authors = [],
  date,
  size = 28,
  style,
  ...rest
}: AuthorStackProps) {
  const list = authors.slice(0, 4);
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 12, ...style }} {...rest}>
      <div style={{ display: "flex" }}>
        {list.map((a, i) => (
          <Avatar
            key={i}
            src={a.avatar}
            initials={a.name ? a.name[0] : undefined}
            size={size}
            style={{ marginLeft: i ? -size * 0.3 : 0, boxShadow: "0 0 0 2px var(--rc-canvas)" }}
          />
        ))}
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 1, minWidth: 0 }}>
        <span style={{ font: "500 14px/1.4 var(--rc-font-sans)", letterSpacing: ".2px", fontFeatureSettings: FEAT, color: "var(--rc-ink)" }}>
          {list.map((a) => a.name).join(", ")}
        </span>
        {date && (
          <span style={{ font: "400 13px/1.4 var(--rc-font-sans)", fontFeatureSettings: FEAT, color: "var(--rc-mute)" }}>{date}</span>
        )}
      </div>
    </div>
  );
}
