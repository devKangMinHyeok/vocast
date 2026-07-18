"use client";
import * as React from "react";
import { Logo, Button } from "@timbre/design-system";
import { Icon } from "../_ui/Icon";
import { asset } from "../../lib/asset";

const HOME = asset("/"); // "/vocast/" on Pages, "/" locally
const LINKS = [
  { label: "Features", href: `${HOME}#features` },
  { label: "Quality", href: `${HOME}#quality` },
  { label: "Privacy", href: `${HOME}#privacy` },
  { label: "AI (MCP)", href: `${HOME}#mcp` },
  { label: "Pricing", href: `${HOME}#pricing` },
  { label: "Blog", href: asset("/blog/") },
];
const FEAT = '"calt","kern","liga","ss03"';
const GITHUB = "https://github.com/devKangMinHyeok/vocast";

function NavLink({
  href,
  children,
  onClick,
  active,
}: {
  href: string;
  children: React.ReactNode;
  onClick?: () => void;
  active?: boolean;
}) {
  return (
    <a
      href={href}
      onClick={onClick}
      style={{
        font: "500 14px/1 var(--rc-font-sans)",
        letterSpacing: ".2px",
        fontFeatureSettings: FEAT,
        color: active ? "var(--rc-ink)" : "var(--rc-body)",
        background: active ? "#1a1b1c" : "transparent",
        padding: "8px 12px",
        borderRadius: "var(--rc-radius-md)",
        transition: "background-color .15s ease, color .15s ease",
        whiteSpace: "nowrap",
      }}
      onMouseEnter={(e) => {
        e.currentTarget.style.background = "#1a1b1c";
        e.currentTarget.style.color = "var(--rc-ink)";
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.background = active ? "#1a1b1c" : "transparent";
        e.currentTarget.style.color = active ? "var(--rc-ink)" : "var(--rc-body)";
      }}
    >
      {children}
    </a>
  );
}

export function Nav({ active }: { active?: string } = {}) {
  const [menuOpen, setMenuOpen] = React.useState(false);
  const [mobile, setMobile] = React.useState(false);

  React.useEffect(() => {
    const onResize = () => {
      const m = window.innerWidth <= 900;
      setMobile(m);
      if (!m) setMenuOpen(false);
    };
    onResize();
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
  }, []);

  return (
    <nav style={{ position: "sticky", top: 14, zIndex: 50, padding: "0 16px" }}>
      <div
        style={{
          maxWidth: 1240,
          margin: "0 auto",
          minHeight: 56,
          display: "flex",
          alignItems: "center",
          gap: 16,
          padding: "0 10px 0 18px",
          borderRadius: 14,
          border: "1px solid var(--rc-hairline)",
          background: "rgba(13,13,13,.72)",
          backdropFilter: "blur(14px)",
          WebkitBackdropFilter: "blur(14px)",
        }}
      >
        <a href={HOME} style={{ display: "inline-flex", flex: "none" }} aria-label="Vocast home">
          <Logo height={22} wordmark="Vocast" />
        </a>
        <div style={{ flex: 1 }} />

        {!mobile && (
          <>
            <div style={{ display: "flex", alignItems: "center", gap: 2 }}>
              {LINKS.map((l) => (
                <NavLink key={l.href} href={l.href} active={active === l.label}>
                  {l.label}
                </NavLink>
              ))}
            </div>
            <span style={{ width: 1, height: 22, background: "var(--rc-hairline)" }} />
            <NavLink href={GITHUB}>GitHub</NavLink>
            <Button variant="primary" size="sm" as="a" href={`${HOME}#pricing`}>
              Buy
            </Button>
          </>
        )}

        {mobile && (
          <button
            onClick={() => setMenuOpen((v) => !v)}
            aria-label="Menu"
            style={{
              display: "inline-flex",
              padding: 8,
              borderRadius: "var(--rc-radius-md)",
              border: "1px solid var(--rc-hairline)",
              background: "transparent",
              color: "var(--rc-ink)",
              cursor: "pointer",
            }}
          >
            <Icon name={menuOpen ? "arrowRight" : "terminal"} size={18} />
          </button>
        )}
      </div>

      {mobile && menuOpen && (
        <div
          style={{
            maxWidth: 1240,
            margin: "8px auto 0",
            display: "flex",
            flexDirection: "column",
            gap: 4,
            padding: 12,
            borderRadius: 14,
            border: "1px solid var(--rc-hairline)",
            background: "rgba(13,13,13,.92)",
            backdropFilter: "blur(14px)",
          }}
        >
          {LINKS.map((l) => (
            <NavLink key={l.href} href={l.href} active={active === l.label} onClick={() => setMenuOpen(false)}>
              {l.label}
            </NavLink>
          ))}
          <NavLink href={GITHUB} onClick={() => setMenuOpen(false)}>
            GitHub
          </NavLink>
          <div style={{ marginTop: 4 }}>
            <Button variant="primary" as="a" href={`${HOME}#pricing`} style={{ width: "100%" }} onClick={() => setMenuOpen(false)}>
              Buy — $49
            </Button>
          </div>
        </div>
      )}
    </nav>
  );
}
