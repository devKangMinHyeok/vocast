"use client";
import * as React from "react";
import { ToolPanel, ReadoutTile, ErrorBox } from "../_ui";
import { LiveWave, WavePeaks } from "../_audio";
import { Icon } from "../../_ui/Icon";
import { audioCtx, decodeFile, computePeaks, bufferToWavBlob, sliceBuffer, fmtTime, fmtSize } from "../lib/audio";

const FEAT = '"calt","kern","liga","ss03"';
const sans = "var(--rc-font-sans)";
const mono = "var(--rc-font-mono)";

type State = "empty" | "active" | "success" | "error";

export function VoiceRecorder() {
  const [state, setState] = React.useState<State>("empty");
  const [err, setErr] = React.useState("");
  const [analyser, setAnalyser] = React.useState<AnalyserNode | null>(null);
  const [elapsed, setElapsed] = React.useState(0);
  const [buf, setBuf] = React.useState<AudioBuffer | null>(null);
  const [peaks, setPeaks] = React.useState<number[]>([]);
  const [trim, setTrim] = React.useState<[number, number]>([0, 1]); // fractions
  const [wavUrl, setWavUrl] = React.useState<string | null>(null);
  const [wavSize, setWavSize] = React.useState(0);
  const streamRef = React.useRef<MediaStream | null>(null);
  const recRef = React.useRef<MediaRecorder | null>(null);
  const timerRef = React.useRef<number | null>(null);

  const cleanupStream = () => { streamRef.current?.getTracks().forEach((t) => t.stop()); streamRef.current = null; setAnalyser(null); if (timerRef.current) clearInterval(timerRef.current); };
  React.useEffect(() => () => { cleanupStream(); if (wavUrl) URL.revokeObjectURL(wavUrl); }, [wavUrl]);

  async function start() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      streamRef.current = stream;
      const ctx = audioCtx();
      await ctx.resume();
      const an = ctx.createAnalyser();
      an.fftSize = 2048;
      ctx.createMediaStreamSource(stream).connect(an);
      setAnalyser(an);
      const chunks: BlobPart[] = [];
      const rec = new MediaRecorder(stream);
      recRef.current = rec;
      rec.ondataavailable = (e) => chunks.push(e.data);
      rec.onstop = async () => {
        cleanupStream();
        try {
          const b = await decodeFile(new Blob(chunks, { type: rec.mimeType || "audio/webm" }));
          setBuf(b);
          setPeaks(computePeaks(b, 200));
          setTrim([0, 1]);
          buildWav(b, 0, 1);
          setState("success");
        } catch {
          setErr("Could not process the recording.");
          setState("error");
        }
      };
      rec.start();
      setElapsed(0);
      setState("active");
      timerRef.current = window.setInterval(() => setElapsed((e) => e + 1), 1000);
    } catch {
      setErr("Microphone access was blocked. Allow the microphone in your browser and try again.");
      setState("error");
    }
  }

  function stop() { recRef.current?.state !== "inactive" && recRef.current?.stop(); if (timerRef.current) clearInterval(timerRef.current); }

  function buildWav(b: AudioBuffer, s: number, e: number) {
    const sliced = sliceBuffer(b, s * b.duration, e * b.duration);
    const blob = bufferToWavBlob(sliced);
    setWavSize(blob.size);
    setWavUrl((prev) => { if (prev) URL.revokeObjectURL(prev); return URL.createObjectURL(blob); });
  }

  function onTrim(next: [number, number]) {
    setTrim(next);
    if (buf) buildWav(buf, next[0], next[1]);
  }

  const reset = () => { if (wavUrl) URL.revokeObjectURL(wavUrl); setWavUrl(null); setBuf(null); setState("empty"); };

  const btn: React.CSSProperties = { display: "inline-flex", alignItems: "center", gap: 8, padding: "11px 18px", borderRadius: 8, cursor: "pointer", font: `600 13.5px/1 ${sans}`, fontFeatureSettings: FEAT };
  const dur = buf ? buf.duration : 0;

  return (
    <ToolPanel>
      {state === "empty" && (
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 16, padding: "clamp(24px,5vw,44px) 24px", textAlign: "center" }}>
          <span style={{ width: 52, height: 52, borderRadius: "50%", display: "inline-flex", alignItems: "center", justifyContent: "center", background: "rgba(255,97,97,.14)", color: "#ff6161" }}><Icon name="record" size={22} /></span>
          <div style={{ font: `500 16px/1.4 ${sans}`, fontFeatureSettings: FEAT, color: "var(--rc-ink)" }}>Record your voice</div>
          <div style={{ maxWidth: 400, font: `400 13.5px/1.6 ${sans}`, fontFeatureSettings: FEAT, color: "var(--rc-mute)" }}>Recording happens in your browser and stays on your device until you download it.</div>
          <button onClick={start} style={{ ...btn, background: "var(--rc-ink)", color: "var(--rc-canvas)", border: "none" }}><Icon name="record" size={16} /> Start recording</button>
        </div>
      )}

      {state === "active" && (
        <div style={{ display: "flex", flexDirection: "column", gap: 18 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <span className="vt-blink" style={{ width: 9, height: 9, borderRadius: "50%", background: "#ff6161" }} />
            <span style={{ font: `500 24px/1 ${mono}`, color: "var(--rc-ink)" }}>{fmtTime(elapsed)}</span>
            <span style={{ font: `400 12px/1 ${mono}`, color: "var(--rc-mute)" }}>recording</span>
          </div>
          <LiveWave analyser={analyser} height={48} />
          <button onClick={stop} style={{ ...btn, alignSelf: "flex-start", background: "var(--rc-ink)", color: "var(--rc-canvas)", border: "none" }}>Stop</button>
        </div>
      )}

      {state === "success" && buf && (
        <div style={{ display: "flex", flexDirection: "column", gap: 18 }}>
          <div style={{ position: "relative" }}>
            <WavePeaks peaks={peaks} height={56} regions={[[0, trim[0]], [trim[1], 1]]} />
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            <div style={{ display: "flex", justifyContent: "space-between", font: `400 12px/1 ${mono}`, color: "var(--rc-mute)" }}>
              <span>trim start {fmtTime(trim[0] * dur)}</span><span>trim end {fmtTime(trim[1] * dur)}</span>
            </div>
            <input type="range" min={0} max={0.98} step={0.01} value={trim[0]} onChange={(e) => onTrim([Math.min(Number(e.target.value), trim[1] - 0.02), trim[1]])} style={{ width: "100%", accentColor: "#f5732b" }} />
            <input type="range" min={0.02} max={1} step={0.01} value={trim[1]} onChange={(e) => onTrim([trim[0], Math.max(Number(e.target.value), trim[0] + 0.02)])} style={{ width: "100%", accentColor: "#f5732b" }} />
          </div>
          {wavUrl && <audio controls src={wavUrl} style={{ width: "100%" }} />}
          <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
            <ReadoutTile label="Length" value={fmtTime((trim[1] - trim[0]) * dur)} />
            <ReadoutTile label="Size" value={fmtSize(wavSize)} />
            <ReadoutTile label="Format" value="WAV" />
          </div>
          <div style={{ display: "flex", gap: 12, flexWrap: "wrap" }}>
            <a href={wavUrl ?? "#"} download="recording.wav" style={{ ...btn, background: "var(--rc-ink)", color: "var(--rc-canvas)", textDecoration: "none" }}><Icon name="download" size={16} /> Download WAV</a>
            <button onClick={reset} style={{ ...btn, background: "transparent", border: "1px solid var(--rc-hairline)", color: "var(--rc-body)" }}>Record again</button>
          </div>
        </div>
      )}

      {state === "error" && <ErrorBox message={err} onRetry={reset} />}
    </ToolPanel>
  );
}
