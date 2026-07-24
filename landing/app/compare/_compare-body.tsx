// Compare page body (locale shared). Body copy is English fallback; nav/links/schema
// stay locale-correct. Korean translation arrives via the design handoff (rule 2).
import * as React from "react";
import { Nav } from "../_sections/Nav";
import { Footer } from "../_sections/Footer";
import { JsonLd } from "../_seo/JsonLd";
import { graph, breadcrumbSchema } from "../../lib/schema";
import type { Lang } from "../../lib/i18n";
import { ComparisonTable, COMPARE_COLUMNS, COMPARE_ROWS, COMPARE_CAPTION } from "./_components";
import { ElevenLabsCost } from "../tools/panels/ElevenLabsCost";

const sans = "var(--rc-font-sans)";
const mono = "var(--rc-font-mono)";

// SEO copy (English fallback). Korean translation is filled by the design handoff.
export const COMPARE_META = {
  title: "Vocast vs cloud voice tools",
  description:
    "An honest look at how Vocast compares to subscription TTS like ElevenLabs and Descript. Vocast runs entirely on your Mac and costs $49 once, with a calculator for when it pays for itself.",
  keywords: [
    "vocast vs elevenlabs",
    "elevenlabs alternative",
    "one-time tts",
    "on-device voice cloning",
    "descript alternative",
  ],
};

export function CompareBody({ lang }: { lang: Lang }) {
  return (
    <main>
      <JsonLd
        data={graph(
          breadcrumbSchema(
            [
              { name: "Home", path: "/" },
              { name: "Compare", path: "/compare/" },
            ],
            lang,
          ),
        )}
      />
      <Nav lang={lang} />
      <div style={{ maxWidth: 1000, margin: "0 auto", padding: "clamp(40px,6vw,64px) 24px 96px" }}>
        {/* eyebrow */}
        <div style={{ display: "flex", alignItems: "center", gap: 6, marginBottom: 26 }}>
          <span style={{ font: `600 16px/1 ${sans}`, color: "var(--rc-ink)" }}>
            Vocast<span style={{ color: "var(--rc-ray)" }}>.</span>
          </span>
          <span
            style={{
              marginLeft: 6,
              font: `500 11px/1 ${mono}`,
              letterSpacing: ".5px",
              textTransform: "uppercase",
              color: "var(--rc-ash)",
            }}
          >
            / compare
          </span>
        </div>

        {/* hero */}
        <h1
          style={{
            margin: "0 0 14px",
            font: `600 clamp(30px,4.4vw,44px)/1.1 ${sans}`,
            letterSpacing: "-.5px",
            color: "var(--rc-ink)",
            textWrap: "balance",
          }}
        >
          Vocast vs cloud voice tools
        </h1>
        <p
          style={{
            margin: "0 0 8px",
            maxWidth: 620,
            font: `400 17px/1.6 ${sans}`,
            color: "var(--rc-mute)",
            textWrap: "pretty",
          }}
        >
          An honest look at how Vocast compares to subscription TTS like ElevenLabs and Descript. Vocast runs entirely
          on this Mac and costs $49 once. Here is where it wins, and where it does not.
        </p>

        {/* comparison table */}
        <div style={{ marginTop: 48 }}>
          <div style={{ display: "flex", alignItems: "baseline", gap: 10, marginBottom: 16 }}>
            <h2 style={{ margin: 0, font: `600 22px/1.3 ${sans}`, letterSpacing: "-.2px", color: "var(--rc-ink)" }}>
              Feature and pricing matrix
            </h2>
          </div>
          <ComparisonTable columns={COMPARE_COLUMNS} rows={COMPARE_ROWS} caption={COMPARE_CAPTION} />
        </div>

        {/* cost calculator */}
        <div style={{ marginTop: 64 }}>
          <div style={{ marginBottom: 16 }}>
            <h2
              style={{
                margin: "0 0 6px",
                font: `600 22px/1.3 ${sans}`,
                letterSpacing: "-.2px",
                color: "var(--rc-ink)",
              }}
            >
              The math over a year
            </h2>
            <p style={{ margin: 0, maxWidth: 560, font: `400 14.5px/1.6 ${sans}`, color: "var(--rc-mute)" }}>
              Drag your monthly narration volume to see when a subscription overtakes a one-time $49.
            </p>
          </div>
          <div style={{ maxWidth: 620 }}>
            <ElevenLabsCost />
          </div>
        </div>
      </div>
      <Footer lang={lang} />
    </main>
  );
}
