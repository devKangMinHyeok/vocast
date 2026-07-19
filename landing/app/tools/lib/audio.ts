// 클라이언트 전용 오디오 헬퍼. 전부 브라우저 안에서 동작 (Web Audio API), 업로드 없음.

let ctx: AudioContext | null = null;
export function audioCtx(): AudioContext {
  if (!ctx) {
    const AC = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
    ctx = new AC();
  }
  return ctx;
}

export async function decodeFile(file: Blob): Promise<AudioBuffer> {
  const arr = await file.arrayBuffer();
  return audioCtx().decodeAudioData(arr);
}

/** 표시용 피크 (0..1) 버킷 배열 */
export function computePeaks(buf: AudioBuffer, buckets: number): number[] {
  const data = buf.getChannelData(0);
  const block = Math.max(1, Math.floor(data.length / buckets));
  const peaks: number[] = [];
  for (let i = 0; i < buckets; i++) {
    let max = 0;
    const start = i * block;
    for (let j = 0; j < block && start + j < data.length; j++) {
      const v = Math.abs(data[start + j]);
      if (v > max) max = v;
    }
    peaks.push(max);
  }
  return peaks;
}

/** AudioBuffer → 16-bit PCM WAV Blob */
export function bufferToWavBlob(buf: AudioBuffer): Blob {
  const numCh = buf.numberOfChannels;
  const sr = buf.sampleRate;
  const total = buf.length * numCh * 2 + 44;
  const ab = new ArrayBuffer(total);
  const view = new DataView(ab);
  const chans: Float32Array[] = [];
  for (let c = 0; c < numCh; c++) chans.push(buf.getChannelData(c));
  let off = 0;
  const str = (s: string) => { for (let i = 0; i < s.length; i++) view.setUint8(off++, s.charCodeAt(i)); };
  str("RIFF"); view.setUint32(off, total - 8, true); off += 4; str("WAVE");
  str("fmt "); view.setUint32(off, 16, true); off += 4;
  view.setUint16(off, 1, true); off += 2;
  view.setUint16(off, numCh, true); off += 2;
  view.setUint32(off, sr, true); off += 4;
  view.setUint32(off, sr * numCh * 2, true); off += 4;
  view.setUint16(off, numCh * 2, true); off += 2;
  view.setUint16(off, 16, true); off += 2;
  str("data"); view.setUint32(off, buf.length * numCh * 2, true); off += 4;
  for (let i = 0; i < buf.length; i++) {
    for (let c = 0; c < numCh; c++) {
      const s = Math.max(-1, Math.min(1, chans[c][i]));
      view.setInt16(off, s < 0 ? s * 0x8000 : s * 0x7fff, true);
      off += 2;
    }
  }
  return new Blob([ab], { type: "audio/wav" });
}

export function sliceBuffer(buf: AudioBuffer, startSec: number, endSec: number): AudioBuffer {
  const sr = buf.sampleRate;
  const s = Math.max(0, Math.floor(startSec * sr));
  const e = Math.min(buf.length, Math.floor(endSec * sr));
  const len = Math.max(1, e - s);
  const out = audioCtx().createBuffer(buf.numberOfChannels, len, sr);
  for (let c = 0; c < buf.numberOfChannels; c++) out.getChannelData(c).set(buf.getChannelData(c).subarray(s, e));
  return out;
}

export interface Region { start: number; end: number } // seconds

/** RMS가 threshold(dBFS) 아래로 minLenMs 이상 지속되는 무음 구간 탐지 */
export function detectSilence(buf: AudioBuffer, thresholdDb: number, minLenMs: number): Region[] {
  const data = buf.getChannelData(0);
  const sr = buf.sampleRate;
  const win = Math.max(1, Math.floor(sr * 0.02)); // 20ms
  const thr = Math.pow(10, thresholdDb / 20);
  const minLen = (minLenMs / 1000) * sr;
  const regions: Region[] = [];
  let runStart = -1;
  for (let i = 0; i < data.length; i += win) {
    let sum = 0;
    let n = 0;
    for (let j = 0; j < win && i + j < data.length; j++) { const v = data[i + j]; sum += v * v; n++; }
    const rms = Math.sqrt(sum / Math.max(1, n));
    const silent = rms < thr;
    if (silent && runStart < 0) runStart = i;
    if (!silent && runStart >= 0) {
      if (i - runStart >= minLen) regions.push({ start: runStart / sr, end: i / sr });
      runStart = -1;
    }
  }
  if (runStart >= 0 && data.length - runStart >= minLen) regions.push({ start: runStart / sr, end: data.length / sr });
  return regions;
}

/** 무음 구간을 제거한 새 AudioBuffer (남은 구간 이어붙이기) */
export function removeSilence(buf: AudioBuffer, regions: Region[]): { out: AudioBuffer; removedSec: number } {
  const sr = buf.sampleRate;
  const numCh = buf.numberOfChannels;
  // 남길 구간 = 무음의 여집합
  const keep: Region[] = [];
  let cursor = 0;
  for (const r of regions) {
    if (r.start > cursor) keep.push({ start: cursor, end: r.start });
    cursor = Math.max(cursor, r.end);
  }
  if (cursor < buf.duration) keep.push({ start: cursor, end: buf.duration });
  const keepLen = keep.reduce((a, r) => a + Math.floor((r.end - r.start) * sr), 0) || 1;
  const out = audioCtx().createBuffer(numCh, keepLen, sr);
  for (let c = 0; c < numCh; c++) {
    const src = buf.getChannelData(c);
    const dst = out.getChannelData(c);
    let w = 0;
    for (const r of keep) {
      const s = Math.floor(r.start * sr);
      const e = Math.floor(r.end * sr);
      dst.set(src.subarray(s, e), w);
      w += e - s;
    }
  }
  const removedSec = regions.reduce((a, r) => a + (r.end - r.start), 0);
  return { out, removedSec };
}

export function fmtTime(sec: number): string {
  const s = Math.max(0, Math.round(sec));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}
export function fmtSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}
