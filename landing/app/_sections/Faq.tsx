"use client";
import * as React from "react";
import { SectionHeading } from "@timbre/design-system";
import { Container } from "../_ui/Container";
import { Section } from "../_ui/Section";
import { FAQ_ITEMS as ITEMS } from "./faq-data";

const FEAT = '"calt","kern","liga","ss03"';

function Row({ q, a, open, onToggle }: { q: string; a: string; open: boolean; onToggle: () => void }) {
  return (
    <div style={{ borderBottom: "1px solid var(--rc-hairline)" }}>
      <button
        onClick={onToggle}
        style={{
          width: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          gap: 16,
          padding: "20px 4px",
          background: "transparent",
          border: "none",
          cursor: "pointer",
          textAlign: "left",
          font: "500 17px/1.4 var(--rc-font-sans)",
          letterSpacing: ".1px",
          fontFeatureSettings: FEAT,
          color: "var(--rc-ink)",
        }}
      >
        {q}
        <span style={{ flex: "none", color: "var(--rc-ray)", fontSize: 22, lineHeight: 1, transform: open ? "rotate(45deg)" : "none", transition: "transform .18s ease" }}>+</span>
      </button>
      <div style={{ maxHeight: open ? 200 : 0, overflow: "hidden", transition: "max-height .24s ease" }}>
        <p style={{ margin: 0, padding: "0 4px 20px", maxWidth: 640, font: "400 15px/1.6 var(--rc-font-sans)", fontFeatureSettings: FEAT, color: "var(--rc-mute)" }}>{a}</p>
      </div>
    </div>
  );
}

export function Faq() {
  const [open, setOpen] = React.useState<number | null>(0);
  return (
    <Section>
      <Container style={{ maxWidth: 820 }}>
        <SectionHeading title="Questions," accent="answered." />
        <div style={{ marginTop: 40 }}>
          {ITEMS.map((it, i) => (
            <Row key={i} q={it.q} a={it.a} open={open === i} onToggle={() => setOpen(open === i ? null : i)} />
          ))}
        </div>
      </Container>
    </Section>
  );
}
