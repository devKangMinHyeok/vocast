import * as React from "react";
import { Logo } from "@timbre/design-system";
import { Container } from "../_ui/Container";
import { asset } from "../../lib/asset";

const FEAT = '"calt","kern","liga","ss03"';
const HOME = asset("/");

const COLUMNS: { title: string; links: { label: string; href: string }[] }[] = [
  {
    title: "Product",
    links: [
      { label: "Features", href: `${HOME}#features` },
      { label: "Pricing", href: `${HOME}#pricing` },
      { label: "AI (MCP)", href: `${HOME}#mcp` },
      { label: "Privacy", href: `${HOME}#privacy` },
    ],
  },
  {
    title: "Resources",
    links: [
      { label: "Blog", href: asset("/blog/") },
      { label: "Quality methodology", href: "https://github.com/devKangMinHyeok/vocast/blob/main/docs/QUALITY.md" },
      { label: "GitHub", href: "https://github.com/devKangMinHyeok/vocast" },
      { label: "Browser demo", href: asset("/demo/") },
    ],
  },
  {
    title: "Company",
    links: [
      { label: "Refund policy", href: `${HOME}#pricing` },
      { label: "Consent & usage", href: "#" },
    ],
  },
];

function FooterLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <a href={href} style={{ font: "400 14px/2 var(--rc-font-sans)", fontFeatureSettings: FEAT, color: "var(--rc-mute)" }}>
      {children}
    </a>
  );
}

export function Footer() {
  return (
    <footer style={{ borderTop: "1px solid var(--rc-hairline)", padding: "56px 0 40px" }}>
      <Container>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 48, justifyContent: "space-between" }}>
          <div style={{ flex: "1 1 260px", maxWidth: 320 }}>
            <Logo height={22} wordmark="Vocast" />
            <p style={{ margin: "16px 0 0", font: "400 14px/1.6 var(--rc-font-sans)", fontFeatureSettings: FEAT, color: "var(--rc-mute)" }}>
              A local Mac voice studio for creators. Your voice, your words, your machine.
            </p>
          </div>
          {COLUMNS.map((c) => (
            <div key={c.title} style={{ display: "flex", flexDirection: "column", gap: 2 }}>
              <div style={{ font: "500 13px/1 var(--rc-font-sans)", letterSpacing: ".4px", textTransform: "uppercase", color: "var(--rc-ash)", marginBottom: 12 }}>
                {c.title}
              </div>
              {c.links.map((l) => (
                <FooterLink key={l.label} href={l.href}>{l.label}</FooterLink>
              ))}
            </div>
          ))}
        </div>
        <div style={{ marginTop: 48, paddingTop: 24, borderTop: "1px solid var(--rc-hairline)", display: "flex", flexWrap: "wrap", gap: 12, justifyContent: "space-between", font: "400 13px/1.5 var(--rc-font-sans)", fontFeatureSettings: FEAT, color: "var(--rc-ash)" }}>
          <span>© 2026 Vocast</span>
          <span>macOS (Apple Silicon) · 100% local · one-time purchase</span>
        </div>
      </Container>
    </footer>
  );
}
