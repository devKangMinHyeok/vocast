// Ported from source/components/content/Prose.jsx — long-form article typography
// with anchored headings and captioned/paired figures.
import * as React from "react";

const FEAT = '"calt","kern","liga","ss03"';

export interface ProseProps extends React.HTMLAttributes<HTMLDivElement> {
  /** max reading width in px (or a CSS length); default 720 */
  measure?: number | string;
}
export interface ProseHeadingProps {
  id?: string;
  level?: 2 | 3;
  children?: React.ReactNode;
}
export interface ProseFigureProps {
  src?: string;
  images?: string[];
  caption?: React.ReactNode;
  pair?: boolean;
  contain?: boolean;
  width?: string | number;
}

const CSS = `
.tb-prose{color:var(--rc-body);font:400 18px/1.75 var(--rc-font-sans);font-feature-settings:${FEAT}}
.tb-prose>*{margin:0 0 24px}
.tb-prose>*:last-child{margin-bottom:0}
.tb-prose h2{position:relative;scroll-margin-top:80px;margin:48px 0 16px;font:600 30px/1.25 var(--rc-font-sans);letter-spacing:.2px;color:var(--rc-ink)}
.tb-prose h3{margin:36px 0 12px;font:500 22px/1.3 var(--rc-font-sans);letter-spacing:.2px;color:var(--rc-ink)}
.tb-prose h2 a.tb-anchor,.tb-prose h3 a.tb-anchor{position:absolute;left:-24px;color:var(--rc-stone);opacity:0;text-decoration:none;transition:opacity .15s}
.tb-prose h2:hover a.tb-anchor,.tb-prose h3:hover a.tb-anchor{opacity:1}
.tb-prose p{color:var(--rc-body)}
.tb-prose a{color:var(--rc-ink);text-decoration:none;border-bottom:1px solid var(--rc-hairline-strong);transition:border-color .15s}
.tb-prose a:hover{border-bottom-color:var(--rc-ray)}
.tb-prose strong{color:var(--rc-ink);font-weight:600}
.tb-prose ul,.tb-prose ol{padding-left:22px;color:var(--rc-body)}
.tb-prose li{margin:0 0 10px}
.tb-prose li::marker{color:var(--rc-ash)}
.tb-prose blockquote{margin:0;padding:6px 0 6px 20px;border-left:2px solid var(--rc-ray);color:var(--rc-charcoal);font-style:italic}
.tb-prose code{font:400 15px/1.5 var(--rc-font-mono);background:var(--rc-surface-elevated);border:1px solid var(--rc-hairline);border-radius:var(--rc-radius-xs);padding:1px 6px;color:var(--rc-ink)}
.tb-prose pre{background:var(--rc-surface);border:1px solid var(--rc-hairline);border-radius:var(--rc-radius-md);padding:18px 20px;overflow:auto}
.tb-prose pre code{background:none;border:none;padding:0;font-size:14px;line-height:1.7;color:var(--rc-body)}
.tb-prose hr{border:none;border-top:1px solid var(--rc-hairline)}`;

function ProseRoot({ children, measure = 720, style, ...rest }: ProseProps) {
  return (
    <div className="tb-prose" style={{ maxWidth: measure, ...style }} {...rest}>
      <style dangerouslySetInnerHTML={{ __html: CSS }} />
      {children}
    </div>
  );
}

/** Anchored section heading — <h2 id> with a hover # link so a TOC can target it. */
function ProseHeading({ id, level = 2, children }: ProseHeadingProps) {
  const Tag = (`h${level}` as unknown) as React.ElementType;
  return (
    <Tag id={id}>
      {id && (
        <a className="tb-anchor" href={`#${id}`} aria-hidden="true">
          #
        </a>
      )}
      {children}
    </Tag>
  );
}

/** Figure with optional caption. Breaks out wider than the prose measure by default. */
function ProseFigure({ src, images, caption, pair = false, contain = false, width }: ProseFigureProps) {
  const imgs = images || (src ? [src] : []);
  const doBreak = width || !contain;
  const breakout: React.CSSProperties = doBreak
    ? { width: width || "min(1040px, 92vw)", position: "relative", left: "50%", transform: "translateX(-50%)" }
    : {};
  return (
    <figure style={{ margin: "40px 0", ...breakout }}>
      <div style={{ display: "flex", gap: 12, borderRadius: "var(--rc-radius-lg)", overflow: "hidden" }}>
        {imgs.map((s, i) => (
          <img
            key={i}
            src={s}
            alt=""
            style={{ flex: pair ? "1 1 0" : "1 1 100%", width: pair ? "50%" : "100%", minWidth: 0, display: "block", borderRadius: "var(--rc-radius-md)", background: "var(--rc-surface-elevated)" }}
          />
        ))}
      </div>
      {caption && (
        <figcaption style={{ marginTop: 14, textAlign: "center", font: "italic 400 14px/1.5 var(--rc-font-sans)", fontFeatureSettings: FEAT, color: "var(--rc-mute)" }}>
          {caption}
        </figcaption>
      )}
    </figure>
  );
}

export const Prose = Object.assign(ProseRoot, {
  Heading: ProseHeading,
  Figure: ProseFigure,
});
