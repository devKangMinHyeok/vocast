"use client";
// "When does Vocast pay for itself" cost calculator. Client component, no network.
// Cumulative cloud spend rises month over month while the flat $49 line holds steady,
// so the crossover reads at a glance. Breakeven is the first month where monthly * m >= 49.
import * as React from "react";

const FEAT = '"calt","kern","liga","ss03"';
const sans = "var(--rc-font-sans)";
const mono = "var(--rc-font-mono)";

// ElevenLabs subscription tiers (placeholder) // as of 2026-07
const TIERS = [
  { name: "Starter", price: 5, minutes: 30 },
  { name: "Creator", price: 22, minutes: 100 },
  { name: "Pro", price: 99, minutes: 500 },
  { name: "Scale", price: 330, minutes: 1500 },
];
const VOCAST = 49; // one-time

const PRESETS = [15, 60, 200, 600];

function pickTier(min: number) {
  return TIERS.find((t) => min <= t.minutes) ?? TIERS[TIERS.length - 1];
}

export function ElevenLabsCost() {
  const [minutes, setMinutes] = React.useState(60);

  const tier = pickTier(minutes);
  const monthly = tier.price;
  const total12 = monthly * 12;

  // cumulative spend + breakeven month
  const cums: number[] = [];
  let breakeven: number | null = null;
  for (let m = 1; m <= 12; m++) {
    const cum = monthly * m;
    cums.push(cum);
    if (breakeven === null && cum >= VOCAST) breakeven = m;
  }

  const maxV = Math.max(total12, VOCAST) * 1.14; // headroom above the tallest bar
  const vocastPct = `${((VOCAST / maxV) * 100).toFixed(1)}%`;

  const breakevenReadout = breakeven !== null ? `month ${breakeven}` : "beyond 12 mo";
  const breakevenSentence =
    breakeven !== null
      ? `At ${minutes} minutes a month, a cloud subscription passes Vocast's $49 in month ${breakeven}. Everything after that is money Vocast keeps in your pocket.`
      : `At ${minutes} minutes a month, the cheapest cloud tier stays under $49 across the first year, but you keep paying every month after.`;
  const tierNote = `Matched to ElevenLabs ${tier.name} at $${monthly}/mo.`;

  const breakevenLeft = breakeven !== null ? `${(((breakeven - 0.5) / 12) * 100).toFixed(2)}%` : undefined;

  return (
    <div
      style={{
        width: "100%",
        fontFamily: sans,
        fontFeatureSettings: FEAT,
        background: "var(--rc-surface)",
        border: "1px solid var(--rc-hairline)",
        borderRadius: 16,
        padding: "22px 22px 24px",
      }}
    >
      {/* Scoped range styling: orange thumb on a hairline track (spec token-exact). */}
      <style>{`
        input[type=range].elc{-webkit-appearance:none;appearance:none;width:100%;height:4px;border-radius:999px;background:var(--rc-hairline);outline:none;margin:0}
        input[type=range].elc::-webkit-slider-thumb{-webkit-appearance:none;appearance:none;width:16px;height:16px;border-radius:999px;background:var(--rc-ray);border:2px solid var(--rc-canvas);cursor:pointer}
        input[type=range].elc::-moz-range-thumb{width:16px;height:16px;border-radius:999px;background:var(--rc-ray);border:2px solid var(--rc-canvas);cursor:pointer}
      `}</style>

      <div
        style={{
          display: "flex",
          alignItems: "baseline",
          justifyContent: "space-between",
          gap: 12,
          flexWrap: "wrap",
          marginBottom: 4,
        }}
      >
        <h3 style={{ margin: 0, font: `600 18px/1.3 ${sans}`, letterSpacing: ".1px", color: "var(--rc-ink)" }}>
          When Vocast pays for itself
        </h3>
        <span style={{ font: `400 12.5px/1.4 ${sans}`, color: "var(--rc-mute)" }}>
          Cloud subscription vs one-time $49
        </span>
      </div>

      {/* controls */}
      <div style={{ marginTop: 18 }}>
        <div
          style={{
            display: "flex",
            alignItems: "baseline",
            justifyContent: "space-between",
            gap: 8,
            marginBottom: 10,
          }}
        >
          <span
            style={{
              font: `500 12px/1 ${mono}`,
              letterSpacing: ".5px",
              textTransform: "uppercase",
              color: "var(--rc-mute)",
            }}
          >
            Narration per month
          </span>
          <span style={{ font: `500 14px/1 ${mono}`, color: "var(--rc-ray)" }}>{minutes} min</span>
        </div>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 14 }}>
          {PRESETS.map((v) => {
            const active = v === minutes;
            return (
              <button
                key={v}
                type="button"
                onClick={() => setMinutes(v)}
                style={{
                  padding: "7px 14px",
                  borderRadius: 999,
                  border: `1px solid ${active ? "var(--rc-ray)" : "var(--rc-hairline)"}`,
                  background: active ? "rgba(245,115,43,.08)" : "var(--rc-surface-elevated)",
                  color: active ? "var(--rc-ink)" : "var(--rc-mute)",
                  font: `500 12.5px/1 ${mono}`,
                  fontFeatureSettings: FEAT,
                  cursor: "pointer",
                  transition: "border-color .15s,color .15s",
                }}
              >
                {v} min
              </button>
            );
          })}
        </div>
        <input
          className="elc"
          type="range"
          min={5}
          max={1500}
          step={5}
          value={minutes}
          onChange={(e) => setMinutes(Number(e.target.value))}
        />
      </div>

      {/* chart */}
      <div
        style={{
          marginTop: 22,
          background: "var(--rc-surface-elevated)",
          border: "1px solid var(--rc-hairline)",
          borderRadius: 12,
          padding: "20px 18px 14px",
        }}
      >
        <div style={{ position: "relative", height: 200, display: "flex", alignItems: "flex-end", gap: 6 }}>
          {/* vocast $49 reference line */}
          <div
            style={{
              position: "absolute",
              left: 0,
              right: 0,
              bottom: vocastPct,
              height: 0,
              borderTop: "1.5px dashed var(--rc-ray)",
              zIndex: 2,
              pointerEvents: "none",
            }}
          />
          <div
            style={{
              position: "absolute",
              left: 2,
              bottom: `calc(${vocastPct} + 5px)`,
              zIndex: 3,
              font: `500 11px/1 ${mono}`,
              color: "var(--rc-ray)",
              pointerEvents: "none",
            }}
          >
            Vocast $49 one-time
          </div>
          {/* breakeven vertical marker over its column */}
          {breakevenLeft ? (
            <div
              style={{
                position: "absolute",
                top: 0,
                bottom: 0,
                left: breakevenLeft,
                width: 0,
                borderLeft: "1.5px dashed var(--rc-ray)",
                opacity: 0.5,
                zIndex: 1,
                pointerEvents: "none",
              }}
            />
          ) : null}
          {cums.map((cum, i) => {
            const m = i + 1;
            const crossed = cum >= VOCAST;
            const h = Math.max(2, (cum / maxV) * 100);
            return (
              <div
                key={m}
                style={{ flex: 1, height: "100%", display: "flex", alignItems: "flex-end", minWidth: 0 }}
              >
                <div
                  style={{
                    width: "100%",
                    height: `${h.toFixed(1)}%`,
                    background: crossed ? "var(--rc-mute)" : "var(--rc-stone)",
                    borderRadius: "4px 4px 0 0",
                    transition: "height .18s var(--rc-ease-out,ease)",
                  }}
                />
              </div>
            );
          })}
        </div>
        <div style={{ display: "flex", gap: 6, marginTop: 8 }}>
          {cums.map((_, i) => {
            const m = i + 1;
            const isBreak = breakeven !== null && m === breakeven;
            return (
              <span
                key={m}
                style={{
                  flex: 1,
                  textAlign: "center",
                  minWidth: 0,
                  font: `400 10px/1 ${mono}`,
                  color: isBreak ? "var(--rc-ray)" : "var(--rc-ash)",
                }}
              >
                {m}
              </span>
            );
          })}
        </div>
        <div
          style={{
            marginTop: 2,
            textAlign: "center",
            font: `400 10.5px/1 ${mono}`,
            letterSpacing: ".5px",
            color: "var(--rc-ash)",
          }}
        >
          month
        </div>
      </div>

      {/* breakeven callout */}
      <p style={{ margin: "16px 0 0", font: `400 14px/1.5 ${sans}`, color: "var(--rc-body)" }}>{breakevenSentence}</p>

      {/* mono readout */}
      <div
        style={{
          marginTop: 14,
          padding: "12px 14px",
          background: "var(--rc-surface-elevated)",
          border: "1px solid var(--rc-hairline)",
          borderRadius: 10,
          font: `500 12.5px/1.5 ${mono}`,
          letterSpacing: ".2px",
          color: "var(--rc-mute)",
          overflowX: "auto",
          whiteSpace: "nowrap",
        }}
      >
        elevenlabs 12-mo: <span style={{ color: "var(--rc-body)" }}>${total12}</span> ·{" "}
        vocast: <span style={{ color: "var(--rc-ray)" }}>$49</span> ·{" "}
        breakeven: <span style={{ color: "var(--rc-body)" }}>{breakevenReadout}</span>
      </div>

      <p style={{ margin: "12px 0 0", font: `400 11.5px/1.5 ${sans}`, color: "var(--rc-ash)" }}>
        {tierNote} Placeholder pricing as of 2026-07, cheapest tier that covers your monthly volume.
      </p>
    </div>
  );
}
