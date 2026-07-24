// Compare page building blocks. Server component only: no state, no hooks.
// Recreated from the Timbre design handoff (design_handoff_compare), token-exact.
import * as React from "react";

const FEAT = '"calt","kern","liga","ss03"';
const sans = "var(--rc-font-sans)";
const mono = "var(--rc-font-mono)";
const TINT = "rgba(245,115,43,.06)";

export interface CompareColumn {
  key: string;
  label: string;
  highlight?: boolean;
}
export type CompareCell =
  | { kind: "yes" }
  | { kind: "no" }
  | { kind: "partial"; note?: string }
  | { kind: "text"; value: string };
export interface CompareRow {
  label: string;
  cells: Record<string, CompareCell>;
  honest?: boolean;
}
export interface ComparisonTableProps {
  columns: CompareColumn[];
  rows: CompareRow[];
  caption?: string;
}

// One mark cell: centered glyph (yes/no/partial) or a value (text). The glyphs are
// kept as characters, not filled cells, so the Vocast column reads as accent, not shout.
function MarkCell({
  cell,
  highlight,
  rowBorder,
}: {
  cell: CompareCell;
  highlight: boolean;
  rowBorder: boolean;
}) {
  let mark = "";
  let markStyle: React.CSSProperties = {};
  let note: string | null = null;

  if (cell.kind === "yes") {
    mark = "✓"; // check
    markStyle = { font: `500 17px/1 ${sans}`, color: highlight ? "var(--rc-ray)" : "var(--rc-ink)" };
  } else if (cell.kind === "no") {
    mark = "–"; // en dash, understated
    markStyle = { font: `400 17px/1 ${sans}`, color: "var(--rc-stone)" };
  } else if (cell.kind === "partial") {
    mark = "≈"; // almost equal
    markStyle = { font: `400 16px/1 ${sans}`, color: "var(--rc-mute)" };
    note = cell.note ?? null;
  } else {
    mark = cell.value || "";
    const isMono = /[0-9$]/.test(mark);
    markStyle = isMono
      ? { font: `500 13.5px/1.35 ${mono}`, letterSpacing: ".2px", color: "var(--rc-body)" }
      : { font: `400 13.5px/1.35 ${sans}`, color: "var(--rc-body)" };
  }

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        textAlign: "center",
        padding: "15px 12px",
        background: highlight ? TINT : undefined,
        borderBottom: rowBorder ? "1px solid var(--rc-hairline)" : undefined,
      }}
    >
      <span style={{ ...markStyle, fontFeatureSettings: FEAT }}>{mark}</span>
      {note ? (
        <span style={{ marginTop: 4, font: `400 11px/1.3 ${mono}`, color: "var(--rc-ash)" }}>{note}</span>
      ) : null}
    </div>
  );
}

export function ComparisonTable({ columns, rows, caption }: ComparisonTableProps) {
  const nCols = columns.length;
  const gridCols = `minmax(180px,1.6fr) repeat(${nCols}, minmax(120px,1fr))`;
  const minWidth = 180 + nCols * 130;

  return (
    <div style={{ width: "100%", fontFamily: sans, fontFeatureSettings: FEAT }}>
      {/* The horizontal scroll lives here, so the page body never scrolls sideways. */}
      <div
        style={{
          overflowX: "auto",
          border: "1px solid var(--rc-hairline)",
          borderRadius: 14,
          background: "var(--rc-surface)",
        }}
      >
        <div style={{ minWidth, display: "grid", gridTemplateColumns: gridCols }}>
          {/* header row */}
          <div
            style={{
              position: "sticky",
              left: 0,
              zIndex: 2,
              background: "var(--rc-surface-elevated)",
              borderBottom: "1px solid var(--rc-hairline)",
              padding: "16px 18px",
            }}
          />
          {columns.map((col) => (
            <div
              key={col.key}
              style={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                justifyContent: "center",
                gap: 4,
                padding: "16px 14px",
                textAlign: "center",
                background: col.highlight
                  ? `linear-gradient(${TINT},${TINT}),var(--rc-surface-elevated)`
                  : "var(--rc-surface-elevated)",
                borderBottom: "1px solid var(--rc-hairline)",
                borderTop: col.highlight ? "2px solid var(--rc-ray)" : undefined,
              }}
            >
              <span
                style={{
                  font: `600 15px/1.2 ${sans}`,
                  letterSpacing: ".2px",
                  color: col.highlight ? "var(--rc-ink)" : "var(--rc-mute)",
                }}
              >
                {col.label}
              </span>
              {col.highlight ? (
                <span
                  style={{
                    font: `500 10px/1 ${mono}`,
                    letterSpacing: ".6px",
                    textTransform: "uppercase",
                    color: "var(--rc-ray)",
                  }}
                >
                  This is us
                </span>
              ) : null}
            </div>
          ))}

          {/* body */}
          {rows.map((row, ri) => {
            const rowBorder = ri !== rows.length - 1;
            return (
              <React.Fragment key={row.label}>
                {/* sticky label cell */}
                <div
                  style={{
                    position: "sticky",
                    left: 0,
                    zIndex: 1,
                    background: "var(--rc-surface)",
                    display: "flex",
                    alignItems: "center",
                    padding: "15px 18px",
                    borderBottom: rowBorder ? "1px solid var(--rc-hairline)" : undefined,
                  }}
                >
                  <span style={{ font: `500 14px/1.35 ${sans}`, color: "var(--rc-mute)" }}>{row.label}</span>
                  {row.honest ? (
                    <span
                      style={{
                        marginLeft: 8,
                        padding: "2px 7px",
                        border: "1px solid var(--rc-hairline)",
                        borderRadius: 999,
                        font: `500 10px/1.2 ${mono}`,
                        letterSpacing: ".4px",
                        textTransform: "uppercase",
                        color: "var(--rc-ash)",
                        verticalAlign: "middle",
                      }}
                    >
                      limitation
                    </span>
                  ) : null}
                </div>
                {columns.map((col) => (
                  <MarkCell
                    key={col.key}
                    cell={row.cells[col.key] ?? { kind: "no" }}
                    highlight={!!col.highlight}
                    rowBorder={rowBorder}
                  />
                ))}
              </React.Fragment>
            );
          })}
        </div>
      </div>
      {caption ? (
        <p style={{ margin: "12px 2px 0", font: `400 12px/1.5 ${sans}`, color: "var(--rc-ash)" }}>{caption}</p>
      ) : null}
    </div>
  );
}

// Realistic sample data so the table renders standalone (Vocast vs cloud TTS).
export const COMPARE_COLUMNS: CompareColumn[] = [
  { key: "vocast", label: "Vocast", highlight: true },
  { key: "elevenlabs", label: "ElevenLabs" },
  { key: "descript", label: "Descript" },
];

export const COMPARE_ROWS: CompareRow[] = [
  {
    label: "Pricing model",
    cells: {
      vocast: { kind: "text", value: "$49 one-time" },
      elevenlabs: { kind: "text", value: "from $5/mo" },
      descript: { kind: "text", value: "from $12/mo" },
    },
  },
  {
    label: "Runs fully on this Mac",
    cells: { vocast: { kind: "yes" }, elevenlabs: { kind: "no" }, descript: { kind: "no" } },
  },
  {
    label: "Works offline",
    cells: {
      vocast: { kind: "yes" },
      elevenlabs: { kind: "no" },
      descript: { kind: "partial", note: "editing only" },
    },
  },
  {
    label: "Voice cloning",
    cells: { vocast: { kind: "yes" }, elevenlabs: { kind: "yes" }, descript: { kind: "yes" } },
  },
  {
    label: "Included voices",
    cells: {
      vocast: { kind: "text", value: "70+" },
      elevenlabs: { kind: "text", value: "300+" },
      descript: { kind: "text", value: "50+" },
    },
  },
  {
    label: "Commercial usage",
    cells: {
      vocast: { kind: "yes" },
      elevenlabs: { kind: "partial", note: "paid tiers" },
      descript: { kind: "yes" },
    },
  },
  {
    label: "Platform",
    honest: true,
    cells: {
      vocast: { kind: "text", value: "macOS Apple Silicon" },
      elevenlabs: { kind: "text", value: "any browser" },
      descript: { kind: "text", value: "macOS, Windows" },
    },
  },
  {
    label: "Cloud voice library updates",
    honest: true,
    cells: { vocast: { kind: "no" }, elevenlabs: { kind: "yes" }, descript: { kind: "yes" } },
  },
];

export const COMPARE_CAPTION =
  "Pricing and voice counts are indicative, as of 2026-07. Vocast is a one-time purchase; competitor prices are the lowest paid tier.";
