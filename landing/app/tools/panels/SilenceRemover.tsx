"use client";
import * as React from "react";
import { ToolPanel, Dropzone, ReadoutTile, ProgressShimmer, ErrorBox } from "../_ui";
import { WavePeaks } from "../_audio";
import { Icon } from "../../_ui/Icon";
import { decodeFile, computePeaks, bufferToWavBlob, sliceBuffer, detectSilence, removeSilence, fmtTime } from "../lib/audio";

const FEAT = '"calt","kern","liga","ss03"';
const sans = "var(--rc-font-sans)";
const mono = "var(--rc-font-mono)";

type State = "empty" | "active" | "success" | "error";
type Mode = "auto" | "manual";

export function SilenceRemover() {
  const [state, setState] = React.useState<State>("empty");
  const [err, setErr] = React.useState("");
  const [buf, setBuf] = React.useState<AudioBuffer | null>(null);
  const [peaks, setPeaks] = React.useState<number[]>([]);
  const [mode, setMode] = React.useState<Mode>("auto");
  const [threshold, setThreshold] = React.useState(-42);
  const [minLen, setMinLen] = React.useState(300);
  const [trim, setTrim] = React.useState<[number, number]>([0, 1]);
  const [name, setName] = React.useState("audio");

  async function run(files: FileList) {
    const file = files[0];
    if (!file) return;
    setState("active");
    setErr("");
    setName(file.name.replace(/\.[^.]+$/, ""));
    try {
      const b = await decodeFile(file);
      setBuf(b);
      setPeaks(computePeaks(b, 240));
      setTrim([0, 1]);
      setState("success");
    } catch {
      setErr("Could not read this file. Try a common audio or video format.");
      setState("error");
    }
  }

  const dur = buf ? buf.duration : 0;
  const regions = React.useMemo(() => (buf && mode === "auto" ? detectSilence(buf, threshold, minLen) : []), [buf, mode, threshold, minLen]);
  const regionFracs: [number, number][] = React.useMemo(
    () => (mode === "auto" ? regions.map((r) => [r.start / dur, r.end / dur] as [number, number]) : [[0, trim[0]], [trim[1], 1]]),
    [mode, regions, dur, trim],
  );

  const result = React.useMemo(() => {
    if (!buf) return null;
    if (mode === "auto") {
      const { out, removedSec } = removeSilence(buf, regions);
      return { blob: bufferToWavBlob(out), removedSec, count: regions.length, newLen: out.duration };
    }
    const sliced = sliceBuffer(buf, trim[0] * dur, trim[1] * dur);
    return { blob: bufferToWavBlob(sliced), removedSec: dur - sliced.duration, count: 0, newLen: sliced.duration };
  }, [buf, mode, regions, trim, dur]);

  const dlUrl = React.useMemo(() => (result ? URL.createObjectURL(result.blob) : null), [result]);
  React.useEffect(() => () => { if (dlUrl) URL.revokeObjectURL(dlUrl); }, [dlUrl]);

  const reset = () => { setBuf(null); setState("empty"); };
  const seg: React.CSSProperties = { padding: "7px 14px", borderRadius: 7, border: "none", cursor: "pointer", font: `500 13px/1 ${sans}`, fontFeatureSettings: FEAT };
  const btn: React.CSSProperties = { display: "inline-flex", alignItems: "center", gap: 8, padding: "11px 18px", borderRadius: 8, cursor: "pointer", font: `600 13.5px/1 ${sans}`, fontFeatureSettings: FEAT };

  return (
    <ToolPanel>
      {state === "empty" && <Dropzone label="Drop an audio or video file" hint="Detected silence is trimmed in your browser. Nothing is uploaded." onFiles={run} />}

      {state === "active" && (
        <div style={{ display: "flex", flexDirection: "column", gap: 16, padding: "8px 0" }}>
          <ProgressShimmer label="Reading the file, on your device" />
        </div>
      )}

      {state === "success" && buf && result && (
        <div style={{ display: "flex", flexDirection: "column", gap: 18 }}>
          <div style={{ display: "inline-flex", background: "var(--rc-surface-elevated)", borderRadius: 10, padding: 4, gap: 4, alignSelf: "flex-start" }}>
            {(["auto", "manual"] as const).map((m) => (
              <button key={m} onClick={() => setMode(m)} style={{ ...seg, textTransform: "capitalize", background: mode === m ? "var(--rc-ink)" : "transparent", color: mode === m ? "var(--rc-canvas)" : "var(--rc-body)" }}>{m === "auto" ? "Auto detect" : "Manual trim"}</button>
            ))}
          </div>

          <WavePeaks peaks={peaks} height={60} regions={regionFracs} />

          {mode === "auto" ? (
            <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
              <label style={{ display: "flex", flexDirection: "column", gap: 6 }}>
                <span style={{ display: "flex", justifyContent: "space-between", font: `400 12px/1 ${mono}`, color: "var(--rc-mute)" }}><span>Silence threshold</span><span>{threshold} dB</span></span>
                <input type="range" min={-60} max={-20} step={1} value={threshold} onChange={(e) => setThreshold(Number(e.target.value))} style={{ accentColor: "#f5732b" }} />
              </label>
              <label style={{ display: "flex", flexDirection: "column", gap: 6 }}>
                <span style={{ display: "flex", justifyContent: "space-between", font: `400 12px/1 ${mono}`, color: "var(--rc-mute)" }}><span>Minimum silence length</span><span>{minLen} ms</span></span>
                <input type="range" min={100} max={1000} step={50} value={minLen} onChange={(e) => setMinLen(Number(e.target.value))} style={{ accentColor: "#f5732b" }} />
              </label>
            </div>
          ) : (
            <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
              <div style={{ display: "flex", justifyContent: "space-between", font: `400 12px/1 ${mono}`, color: "var(--rc-mute)" }}><span>start {fmtTime(trim[0] * dur)}</span><span>end {fmtTime(trim[1] * dur)}</span></div>
              <input type="range" min={0} max={0.98} step={0.01} value={trim[0]} onChange={(e) => setTrim([Math.min(Number(e.target.value), trim[1] - 0.02), trim[1]])} style={{ accentColor: "#f5732b" }} />
              <input type="range" min={0.02} max={1} step={0.01} value={trim[1]} onChange={(e) => setTrim([trim[0], Math.max(Number(e.target.value), trim[0] + 0.02)])} style={{ accentColor: "#f5732b" }} />
            </div>
          )}

          <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
            <ReadoutTile label="Removed" value={fmtTime(result.removedSec)} tone="accent" />
            {mode === "auto" && <ReadoutTile label="Regions" value={String(result.count)} />}
            <ReadoutTile label="New length" value={fmtTime(result.newLen)} />
          </div>
          {dlUrl && <audio controls src={dlUrl} style={{ width: "100%" }} />}
          <div style={{ display: "flex", gap: 12, flexWrap: "wrap" }}>
            <a href={dlUrl ?? "#"} download={`${name}_trimmed.wav`} style={{ ...btn, background: "var(--rc-ink)", color: "var(--rc-canvas)", textDecoration: "none" }}><Icon name="download" size={16} /> Download WAV</a>
            <button onClick={reset} style={{ ...btn, background: "transparent", border: "1px solid var(--rc-hairline)", color: "var(--rc-body)" }}>Start over</button>
          </div>
        </div>
      )}

      {state === "error" && <ErrorBox message={err} onRetry={reset} />}
    </ToolPanel>
  );
}
