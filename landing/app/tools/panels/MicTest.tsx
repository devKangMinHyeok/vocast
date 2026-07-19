"use client";
import * as React from "react";
import { ToolPanel, ReadoutTile, ErrorBox } from "../_ui";
import { LiveWave, LevelMeter, useLevel } from "../_audio";
import { Icon } from "../../_ui/Icon";
import { audioCtx } from "../lib/audio";

const FEAT = '"calt","kern","liga","ss03"';
const sans = "var(--rc-font-sans)";

type State = "empty" | "active" | "error";

export function MicTest() {
  const [state, setState] = React.useState<State>("empty");
  const [err, setErr] = React.useState("");
  const [analyser, setAnalyser] = React.useState<AnalyserNode | null>(null);
  const [sampleUrl, setSampleUrl] = React.useState<string | null>(null);
  const [recording, setRecording] = React.useState(false);
  const streamRef = React.useRef<MediaStream | null>(null);
  const { level, clipping, db } = useLevel(analyser);

  const stopAll = React.useCallback(() => {
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
    setAnalyser(null);
    if (sampleUrl) URL.revokeObjectURL(sampleUrl);
    setSampleUrl(null);
    setState("empty");
  }, [sampleUrl]);

  React.useEffect(() => () => { streamRef.current?.getTracks().forEach((t) => t.stop()); }, []);

  async function start() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      streamRef.current = stream;
      const ctx = audioCtx();
      await ctx.resume();
      const src = ctx.createMediaStreamSource(stream);
      const an = ctx.createAnalyser();
      an.fftSize = 2048;
      src.connect(an);
      setAnalyser(an);
      setState("active");
    } catch {
      setErr("Microphone access was blocked. Allow the microphone in your browser and try again.");
      setState("error");
    }
  }

  function recordSample() {
    if (!streamRef.current) return;
    setRecording(true);
    const rec = new MediaRecorder(streamRef.current);
    const chunks: BlobPart[] = [];
    rec.ondataavailable = (e) => chunks.push(e.data);
    rec.onstop = () => {
      setSampleUrl(URL.createObjectURL(new Blob(chunks, { type: rec.mimeType || "audio/webm" })));
      setRecording(false);
    };
    rec.start();
    setTimeout(() => rec.state !== "inactive" && rec.stop(), 5000);
  }

  const quality = db < -48 ? "low" : clipping ? "too hot" : "good";
  const qTone = quality === "good" ? "ok" : undefined;

  const btn: React.CSSProperties = { display: "inline-flex", alignItems: "center", gap: 8, padding: "11px 18px", borderRadius: 8, border: "none", cursor: "pointer", font: `600 13.5px/1 ${sans}`, fontFeatureSettings: FEAT };

  return (
    <ToolPanel>
      {state === "empty" && (
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 16, padding: "clamp(24px,5vw,44px) 24px", textAlign: "center" }}>
          <span style={{ width: 52, height: 52, borderRadius: 12, display: "inline-flex", alignItems: "center", justifyContent: "center", background: "rgba(245,115,43,.12)", color: "var(--rc-ray)" }}><Icon name="mic" size={24} /></span>
          <div style={{ font: `500 16px/1.4 ${sans}`, fontFeatureSettings: FEAT, color: "var(--rc-ink)" }}>Check your microphone</div>
          <div style={{ maxWidth: 400, font: `400 13.5px/1.6 ${sans}`, fontFeatureSettings: FEAT, color: "var(--rc-mute)" }}>Your browser will ask for microphone access. Nothing is recorded or uploaded until you choose to record a sample.</div>
          <button onClick={start} style={{ ...btn, background: "var(--rc-ink)", color: "var(--rc-canvas)" }}><Icon name="mic" size={16} /> Start microphone</button>
        </div>
      )}

      {state === "active" && (
        <div style={{ display: "flex", flexDirection: "column", gap: 18 }}>
          <LiveWave analyser={analyser} />
          <LevelMeter level={level} clipping={clipping} />
          <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
            <ReadoutTile label="Level" value={`${db > -90 ? db.toFixed(0) : "-inf"} dB`} />
            <ReadoutTile label="Clipping" value={clipping ? "yes" : "no"} tone={clipping ? undefined : "ok"} />
            <ReadoutTile label="Quality" value={quality} tone={qTone} />
          </div>
          <div style={{ display: "flex", gap: 12, flexWrap: "wrap", alignItems: "center" }}>
            <button onClick={recordSample} disabled={recording} style={{ ...btn, background: "var(--rc-ink)", color: "var(--rc-canvas)", opacity: recording ? 0.6 : 1 }}>
              {recording ? "Recording 5 seconds…" : "Record a 5 second sample"}
            </button>
            <button onClick={stopAll} style={{ ...btn, background: "transparent", border: "1px solid var(--rc-hairline)", color: "var(--rc-body)" }}>Stop</button>
          </div>
          {sampleUrl && (
            <div>
              <div style={{ font: `400 12.5px/1 ${sans}`, fontFeatureSettings: FEAT, color: "var(--rc-mute)", marginBottom: 8 }}>Play back your sample:</div>
              <audio controls src={sampleUrl} style={{ width: "100%" }} />
            </div>
          )}
        </div>
      )}

      {state === "error" && <ErrorBox message={err} onRetry={() => setState("empty")} />}
    </ToolPanel>
  );
}
