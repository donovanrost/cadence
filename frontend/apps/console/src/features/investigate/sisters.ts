import type { SeriesPoint } from "@/ui";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";

/**
 * B4 drawing helpers (Investigate.md §B4): the mini plane ring, the 80×24 sparkline, and the
 * row's `AOS T−52m`. Only what the fleet read and M10 history say; nothing propagated (#4).
 */
export type RingTone = "self" | "crit" | "caution" | "other";
export type RingDot = Readonly<{ id: string; x: number; y: number; tone: RingTone; label: string }>;

/**
 * Dots around a ring for the plane's spacecraft: by phase when every one has it, else evenly by
 * slot (then SCID). The selected one is `self`; sisters carry their alarm severity.
 */
export function ringDots(
  fleet: readonly FleetSpacecraft[],
  sc: FleetSpacecraft,
  sisters: ReadonlyMap<string, "crit" | "caution">,
  radius = 40,
  center = 50,
): RingDot[] {
  if (sc.plane === null) return [];
  const plane = fleet
    .filter((o) => o.plane === sc.plane)
    .sort((a, b) => (a.slot ?? a.scid) - (b.slot ?? b.scid) || a.scid - b.scid);
  const phased = plane.every((o) => o.phase_deg !== null);
  return plane.map((o, i) => {
    const deg = phased ? (o.phase_deg ?? 0) : (360 * i) / plane.length;
    const rad = ((deg - 90) * Math.PI) / 180;
    return {
      id: o.id,
      x: Math.round((center + radius * Math.cos(rad)) * 10) / 10,
      y: Math.round((center + radius * Math.sin(rad)) * 10) / 10,
      tone: o.id === sc.id ? "self" : (sisters.get(o.id) ?? "other"),
      label: o.name,
    };
  });
}

/** Sparkline polyline points over the series' own range (means), or null with under 2 points. */
export function sparkPoints(
  series: readonly SeriesPoint[],
  width = 80,
  height = 24,
): string | null {
  if (series.length < 2) return null;
  const t0 = series[0]?.t ?? 0;
  const t1 = series.at(-1)?.t ?? t0;
  const lo = Math.min(...series.map((p) => p.mean));
  const hi = Math.max(...series.map((p) => p.mean));
  const x = (t: number) => (t1 === t0 ? 0 : ((t - t0) / (t1 - t0)) * width);
  const y = (v: number) =>
    hi === lo ? height / 2 : height - 1 - ((v - lo) / (hi - lo)) * (height - 2);
  return series.map((p) => `${x(p.t).toFixed(1)},${y(p.mean).toFixed(1)}`).join(" ");
}

/** `AOS T−52m`, `AOS T−3h 10m`, `IN CONTACT`; null when nothing is booked. */
export function aosShort(sc: FleetSpacecraft, now: Date): string | null {
  if (sc.in_contact) return "IN CONTACT";
  if (!sc.next_aos_at) return null;
  const min = Math.round((Date.parse(sc.next_aos_at) - now.getTime()) / 60_000);
  if (min < 0) return null;
  return min < 60 ? `AOS T−${min}m` : `AOS T−${Math.floor(min / 60)}h ${min % 60}m`;
}
