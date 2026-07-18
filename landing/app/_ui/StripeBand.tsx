import * as React from "react";
import { Button } from "@timbre/design-system";
import { Container } from "./Container";
import { asset } from "../../lib/asset";

const FEAT = '"calt","kern","liga","ss03"';

/** Closing band with the diagonal brand-orange stripe (used at the foot of blog posts). */
export function StripeBand() {
  return (
    <section style={{ position: "relative", overflow: "hidden" }}>
      {/* diagonal orange stripe */}
      <div
        aria-hidden
        style={{
          position: "absolute",
          inset: "-40% -10%",
          background: "linear-gradient(100.41deg, #ff9448 0.52%, #e0561c 100%)",
          transform: "rotate(-4deg)",
          opacity: 0.14,
          pointerEvents: "none",
        }}
      />
      <Container style={{ position: "relative" }}>
        <div
          style={{
            display: "flex",
            flexWrap: "wrap",
            gap: 20,
            alignItems: "center",
            justifyContent: "space-between",
            padding: "48px 0",
          }}
        >
          <div>
            <div style={{ font: "600 26px/1.2 var(--rc-font-sans)", letterSpacing: "-.2px", fontFeatureSettings: FEAT, color: "var(--rc-ink)" }}>
              Read your next script in your own voice.
            </div>
            <div style={{ marginTop: 6, font: "400 15px/1.5 var(--rc-font-sans)", fontFeatureSettings: FEAT, color: "var(--rc-mute)" }}>
              One-time, 100% local. macOS (Apple Silicon).
            </div>
          </div>
          <Button variant="primary" as="a" href={`${asset("/")}#pricing`}>
            Own it for $49
          </Button>
        </div>
      </Container>
    </section>
  );
}
