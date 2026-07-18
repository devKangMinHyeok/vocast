// Ported from source/components/content/CategoryTag.jsx — blog category pill.
import * as React from "react";

const FEAT = '"calt","kern","liga","ss03"';

export interface CategoryTagProps extends React.HTMLAttributes<HTMLElement> {
  /** Timbre-orange tint instead of neutral surface */
  accent?: boolean;
  as?: React.ElementType;
  href?: string;
}

export function CategoryTag({
  children,
  accent = false,
  as: Tag = "span",
  style,
  ...rest
}: CategoryTagProps) {
  return (
    <Tag
      style={{
        display: "inline-flex",
        alignItems: "center",
        font: "500 12px/1 var(--rc-font-sans)",
        letterSpacing: ".3px",
        fontFeatureSettings: FEAT,
        padding: "5px 10px",
        borderRadius: "var(--rc-radius-full)",
        whiteSpace: "nowrap",
        color: accent ? "var(--rc-ray)" : "var(--rc-body)",
        background: accent ? "rgba(245,115,43,0.12)" : "var(--rc-surface-elevated)",
        border: `1px solid ${accent ? "rgba(245,115,43,0.28)" : "var(--rc-hairline)"}`,
        textDecoration: "none",
        ...style,
      }}
      {...rest}
    >
      {children}
    </Tag>
  );
}
