import { formatCount } from "@/ui";
import type { Pass } from "./api.ts";

/**
 * ux U67: bytes at the end of a pass that didn't form a complete frame or packet. A stream that
 * stops mid-frame is normal, so it's a quiet data-quality note in the pass's view only, never on
 * Now or the Timeline, and only for a side that's above zero.
 */
export function cutOffWords(c: Pass["incomplete_at_end"]): string | null {
  if (!c) return null;
  const f = c.frame_bytes;
  const p = c.packet_bytes;
  const head = (n: number) =>
    `${n === 1 ? "1 byte" : `${formatCount(n)} bytes`} at the end of the pass`;
  if (f > 0 && p > 0)
    return `${head(f)} didn't form a complete frame, and ${formatCount(p)} didn't form a complete packet, so they weren't stored.`;
  const n = f > 0 ? f : p;
  if (n <= 0) return null;
  const what = f > 0 ? "frame" : "packet";
  return `${head(n)} didn't form a complete ${what}, so ${n === 1 ? "it wasn't" : "they weren't"} stored.`;
}
