"use client";
import * as React from "react";

const RAY = "#f5732b";

/** AnalyserNode를 rAF로 그리는 실시간 막대 파형 (녹음/청취 피드백) */
export function LiveWave({ analyser, color = RAY, height = 44 }: { analyser: AnalyserNode | null; color?: string; height?: number }) {
  const ref = React.useRef<HTMLCanvasElement>(null);
  React.useEffect(() => {
    const cv = ref.current;
    if (!cv || !analyser) return;
    const g = cv.getContext("2d");
    if (!g) return;
    const dpr = window.devicePixelRatio || 1;
    const buf = new Uint8Array(analyser.fftSize);
    let raf = 0;
    const draw = () => {
      const w = (cv.width = Math.max(1, cv.clientWidth * dpr));
      const h = (cv.height = height * dpr);
      analyser.getByteTimeDomainData(buf);
      g.clearRect(0, 0, w, h);
      const bars = Math.max(8, Math.floor(cv.clientWidth / 5));
      const step = Math.floor(buf.length / bars);
      const bw = w / bars;
      g.fillStyle = color;
      for (let i = 0; i < bars; i++) {
        let peak = 0;
        for (let j = 0; j < step; j++) { const v = Math.abs(buf[i * step + j] - 128) / 128; if (v > peak) peak = v; }
        const bh = Math.max(2 * dpr, peak * h * 0.92);
        g.globalAlpha = 0.55 + peak * 0.45;
        const x = i * bw + bw * 0.2;
        g.fillRect(x, (h - bh) / 2, bw * 0.6, bh);
      }
      g.globalAlpha = 1;
      raf = requestAnimationFrame(draw);
    };
    raf = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(raf);
  }, [analyser, color, height]);
  return <canvas ref={ref} style={{ width: "100%", height, display: "block" }} />;
}

/** 정적 피크 막대 파형 + (옵션) 무음 구간 빨강 오버레이. regions는 0..1 비율 [start,end]. */
export function WavePeaks({ peaks, color = RAY, height = 44, regions }: { peaks: number[]; color?: string; height?: number; regions?: [number, number][] }) {
  const ref = React.useRef<HTMLCanvasElement>(null);
  React.useEffect(() => {
    const cv = ref.current;
    if (!cv) return;
    const g = cv.getContext("2d");
    if (!g) return;
    const dpr = window.devicePixelRatio || 1;
    const w = (cv.width = Math.max(1, cv.clientWidth * dpr));
    const h = (cv.height = height * dpr);
    g.clearRect(0, 0, w, h);
    if (regions) {
      g.fillStyle = "rgba(255,97,97,.16)";
      for (const [s, e] of regions) g.fillRect(s * w, 0, Math.max(1, (e - s) * w), h);
    }
    const n = peaks.length || 1;
    const bw = w / n;
    g.fillStyle = color;
    for (let i = 0; i < n; i++) {
      const bh = Math.max(2 * dpr, peaks[i] * h * 0.92);
      g.fillRect(i * bw + bw * 0.15, (h - bh) / 2, bw * 0.7, bh);
    }
  }, [peaks, color, height, regions]);
  return <canvas ref={ref} style={{ width: "100%", height, display: "block" }} />;
}

/** 입력 레벨 미터 (0..1). safe 구간 표시 + 클리핑 시 빨강. */
export function LevelMeter({ level, clipping }: { level: number; clipping: boolean }) {
  const pct = Math.max(0, Math.min(1, level)) * 100;
  return (
    <div>
      <div style={{ position: "relative", height: 10, borderRadius: 5, background: "var(--rc-surface-elevated)", overflow: "hidden" }}>
        {/* safe zone marker (대략 -24..-6 dBFS) */}
        <span style={{ position: "absolute", top: 0, bottom: 0, left: "18%", width: "58%", background: "rgba(89,212,153,.10)", borderLeft: "1px solid rgba(89,212,153,.35)", borderRight: "1px solid rgba(89,212,153,.35)" }} />
        <div style={{ position: "absolute", top: 0, bottom: 0, left: 0, width: `${pct}%`, background: clipping ? "#ff6161" : "#59d499", transition: "width .06s linear" }} />
      </div>
    </div>
  );
}

/** analyser에서 RMS(dBFS)와 클리핑 여부를 rAF로 폴링하는 훅 */
export function useLevel(analyser: AnalyserNode | null) {
  const [level, setLevel] = React.useState(0);
  const [clipping, setClipping] = React.useState(false);
  const [db, setDb] = React.useState(-90);
  React.useEffect(() => {
    if (!analyser) return;
    const buf = new Uint8Array(analyser.fftSize);
    let raf = 0;
    const tick = () => {
      analyser.getByteTimeDomainData(buf);
      let sum = 0;
      let peak = 0;
      for (let i = 0; i < buf.length; i++) {
        const v = (buf[i] - 128) / 128;
        sum += v * v;
        if (Math.abs(v) > peak) peak = Math.abs(v);
      }
      const rms = Math.sqrt(sum / buf.length);
      const d = 20 * Math.log10(rms || 1e-6);
      setDb(d);
      setLevel(Math.max(0, (d + 60) / 60)); // -60..0 dB → 0..1
      setClipping(peak > 0.985);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [analyser]);
  return { level, clipping, db };
}
