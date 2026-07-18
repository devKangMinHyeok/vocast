// Ported from source/components/media/Avatar.jsx — circular avatar (image or initials).
import * as React from "react";

export interface AvatarProps extends React.HTMLAttributes<HTMLSpanElement> {
  src?: string;
  alt?: string;
  initials?: string;
  size?: number;
}

export function Avatar({ src, alt = "", initials, size = 32, style, ...rest }: AvatarProps) {
  return (
    <span
      style={{
        width: size,
        height: size,
        flex: "none",
        borderRadius: "var(--rc-radius-full)",
        overflow: "hidden",
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        background: "var(--rc-surface-card)",
        border: "1px solid var(--rc-hairline)",
        color: "var(--rc-body)",
        font: `500 ${Math.round(size * 0.4)}px/1 var(--rc-font-sans)`,
        ...style,
      }}
      {...rest}
    >
      {src ? (
        <img src={src} alt={alt} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
      ) : (
        initials
      )}
    </span>
  );
}
