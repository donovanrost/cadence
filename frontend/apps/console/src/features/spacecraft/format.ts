import { formatDuration, formatShort } from "@/ui";

const two = (n: number) => String(n).padStart(2, "0");

/** One orbit format everywhere (ux review 2026-11-08): `P01 · slot 01`, `P01`, or null. */
export function orbitLabel(plane: number | null, slot: number | null): string | null {
  if (plane === null) return null;
  return slot === null ? `P${two(plane)}` : `P${two(plane)} · slot ${two(slot)}`;
}

/** `11-08 22:30Z · T+1m 05s` (design-language §4: an absolute time carries its distance). */
export function heardLabel(at: string, now: Date): string {
  const when = new Date(at);
  const ago = Math.max(0, (now.getTime() - when.getTime()) / 1000);
  return `${formatShort(when)} · T+${formatDuration(ago)}`;
}
