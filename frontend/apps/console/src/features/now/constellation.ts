import type { FleetSpacecraft, FleetState } from "@/features/fleet/index.ts";

/**
 * Schematic constellation (design-language ApConstellation): each plane is an ellipse around the
 * Earth disc, tilted by its rank among the planes, and each spacecraft sits at its in-plane phase.
 * This is a drawing of the fleet's structure, not a propagation: no positions are predicted
 * (DECISIONS #4), so there is no ground-track mode.
 */

export const VIEW = { w: 560, h: 480, cx: 280, cy: 240, earthR: 124, rx: 236, ry: 64 } as const;

const DOT_R: Readonly<Record<FleetState, number>> = {
  critical: 3.5,
  caution: 2.6,
  stale: 2.6,
  nominal: 1.8,
  never_heard: 1.8,
};

export type Dot = Readonly<{
  id: string;
  name: string;
  state: FleetState;
  plane: number;
  x: number;
  y: number;
  r: number;
  /** Behind the Earth's limb plane (drawn dimmed). */
  back: boolean;
}>;

export type Orbit = Readonly<{ plane: number; back: string; front: string }>;

export type Constellation = Readonly<{ orbits: readonly Orbit[]; dots: readonly Dot[] }>;

const f = (n: number) => n.toFixed(1);

function projector(rank: number, planes: number) {
  const tilt = ((rank * 180) / Math.max(planes, 1) - 81) * (Math.PI / 180);
  const ca = Math.cos(tilt);
  const sa = Math.sin(tilt);
  return (t: number): [number, number] => {
    const x0 = VIEW.rx * Math.cos(t);
    const y0 = VIEW.ry * Math.sin(t);
    return [VIEW.cx + x0 * ca - y0 * sa, VIEW.cy + x0 * sa + y0 * ca];
  };
}

function arc(point: (t: number) => [number, number], from: number): string {
  let d = "";
  for (let k = 0; k <= 48; k++) {
    const [x, y] = point(from + (k / 48) * Math.PI);
    d += `${k ? "L" : "M"}${f(x)} ${f(y)}`;
  }
  return d;
}

/** Null when no spacecraft has both a plane and a phase: the panel shows "not available". */
export function constellation(fleet: readonly FleetSpacecraft[]): Constellation | null {
  const placed = fleet.filter((sc) => sc.plane !== null && sc.phase_deg !== null);
  if (placed.length === 0) return null;
  const planes = [...new Set(placed.map((sc) => sc.plane ?? 0))].sort((a, b) => a - b);
  const rank = new Map(planes.map((plane, i) => [plane, i]));
  const projectors = planes.map((_, i) => projector(i, planes.length));

  const orbits = planes.map((plane, i) => {
    const point = projectors[i] ?? projector(i, planes.length);
    return { plane, back: arc(point, Math.PI), front: arc(point, 0) };
  });

  const dots: Dot[] = [];
  for (const sc of placed) {
    const plane = sc.plane ?? 0;
    const point = projectors[rank.get(plane) ?? 0];
    if (!point) continue;
    const t = ((sc.phase_deg ?? 0) * Math.PI) / 180;
    const [x, y] = point(t);
    const back = Math.sin(t) < 0;
    if (back && Math.hypot(x - VIEW.cx, y - VIEW.cy) < VIEW.earthR + 2) continue;
    dots.push({ id: sc.id, name: sc.name, state: sc.state, plane, x, y, r: DOT_R[sc.state], back });
  }
  return { orbits, dots };
}
