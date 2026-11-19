import { formatValue, withUnit } from "@/features/alarms/index.ts";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import { pointLimits, type TelemetryPoint } from "@/features/telemetry/index.ts";
import type { PaletteItem } from "./results.ts";

/**
 * ⌘K Telemetry group (Palette.md, M23 point search). `312 vbat` scopes the search to that
 * spacecraft and shows its latest value; plain `vbat` searches the mission's point set.
 * ↵ opens Telemetry with the point plotted (the spacecraft Telemetry tab isn't built yet).
 */
export type TelemetryQuery = Readonly<{ q: string; spacecraft: FleetSpacecraft | null }>;

/** Null when there's nothing worth asking the server (under 2 characters). */
export function telemetryQuery(
  text: string,
  fleet: readonly FleetSpacecraft[],
): TelemetryQuery | null {
  const [first = "", ...rest] = text.trim().split(/\s+/);
  const sc = fleet.find(
    (s) => String(s.scid) === first || s.name.toLowerCase() === first.toLowerCase(),
  );
  if (sc && rest.length) {
    const q = rest.join(" ");
    return q.length >= 1 ? { q, spacecraft: sc } : null;
  }
  const q = text.trim();
  return q.length >= 2 ? { q, spacecraft: null } : null;
}

export function pointItems(
  points: readonly TelemetryPoint[],
  spacecraft: FleetSpacecraft | null,
): PaletteItem[] {
  return points.map((p, rank) => {
    const latest = p.latest ?? null;
    const value = latest ? withUnit(formatValue(latest.value), p.unit) : null;
    const where = p.subsystem ? `${p.subsystem} · ${p.id}` : p.id;
    return {
      key: `pt-${spacecraft?.id ?? "any"}-${p.id}`,
      group: "Telemetry",
      title: spacecraft ? `${spacecraft.scid} › ${p.name}` : p.name,
      subtitle: [spacecraft ? (value ?? "No recent value") : null, p.description, where]
        .filter((s): s is string => Boolean(s))
        .join(" · "),
      hint: "PLOT",
      state: latest ? pointLimits(p).mark : null,
      to: {
        name: "ops.telemetry",
        query: { ...(spacecraft ? { sc: String(spacecraft.scid) } : {}), p: p.id },
      },
      commandTo: null,
      rank,
    };
  });
}
