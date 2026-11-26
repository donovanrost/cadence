import type { MissionId } from "@/api/index.ts";
import { computed, type Ref } from "vue";
import { useFleet } from "@/features/fleet/index.ts";

export type SpacecraftName = Readonly<{ name: string; scid: number }>;

/** Spacecraft id → name + SCID for plan rows and bars (identity on every line, CommandFlow R01). */
export function useSpacecraftNames(missionId: Readonly<Ref<MissionId>>) {
  const fleet = useFleet(missionId, { live: false });
  const byId = computed(() => {
    const s = fleet.state.value;
    const map = new Map<string, SpacecraftName>();
    if (s.status === "ready")
      for (const sc of s.value.spacecraft) map.set(sc.id, { name: sc.name, scid: sc.scid });
    return map;
  });
  return (id: string | null): SpacecraftName | null => (id ? (byId.value.get(id) ?? null) : null);
}

/**
 * #237 (U25): a craft's name from the fleet, or "Unknown spacecraft" when it can't be named.
 * Never its id: an id read as a name is meaningless to an operator and hides that the name
 * couldn't be read.
 */
export const craftLabel = (name: SpacecraftName | null): string =>
  name?.name.trim() ? name.name : "Unknown spacecraft";

/** `FRI 24 OCT` for header lines; days are UTC (U22 Q1). */
export function dayLabel(day: string): string {
  const d = new Date(`${day}T00:00:00Z`);
  return d
    .toLocaleDateString("en-GB", {
      weekday: "short",
      day: "2-digit",
      month: "short",
      timeZone: "UTC",
    })
    .replaceAll(",", "")
    .toUpperCase();
}
