import type { MissionId } from "@/api/index.ts";
import { computed, type Ref } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { useNow } from "@/ui";
import { fetchGroups, usePeopleNames } from "@/features/commands/index.ts";
import { useFleet } from "@/features/fleet/index.ts";
import { alarmItems, phoneSpacecraftItems, requestItems } from "./mobile.ts";
import { useAlarmSearch } from "./useAlarmSearch.ts";
import type { Group, PaletteItem } from "./results.ts";

export type SourceState = "loading" | "ready" | "failed";

/**
 * The phone sheet's three reads. Requests and the fleet are read once when the sheet opens and
 * matched locally; the alarms are searched on the server as the text settles (#827: the worst 200
 * alarms are not the alarms). Each group reports its own state: a failed read shows its own Try
 * again (ux 68d12603).
 */
export function useMobileSearch(missionId: Ref<MissionId>, raw: Ref<string>) {
  const now = useNow();
  const fleet = useFleet(missionId, { live: false });
  const requests = useRemoteQuery(missionId, (m, signal) => fetchGroups(m, {}, signal));
  useMissionInvalidation(missionId, ["commanding"], requests.refetch);
  const nameOf = usePeopleNames();

  const spacecraft = computed(() =>
    fleet.state.value.status === "ready" ? fleet.state.value.value.spacecraft : [],
  );
  const byId = computed(() => new Map(spacecraft.value.map((sc) => [sc.id, sc])));
  const text = computed(() => raw.value.trim().toLowerCase());
  const alarms = useAlarmSearch(missionId, raw, spacecraft);

  const items = computed<PaletteItem[]>(() => {
    const t = now.value.getTime();
    const r = requests.state.value;
    return [
      ...(alarms.state.value === "ready"
        ? alarmItems(alarms.alarms.value, byId.value, text.value, t)
        : []),
      ...(r.status === "ready" ? requestItems(r.value, text.value, nameOf, t) : []),
      ...phoneSpacecraftItems(spacecraft.value, text.value),
    ];
  });

  const stateOf = (s: { status: string }): SourceState =>
    s.status === "ready" ? "ready" : s.status === "loading" ? "loading" : "failed";
  const sources = computed<Readonly<Partial<Record<Group, SourceState>>>>(() => ({
    Alarms: alarms.state.value,
    Requests: stateOf(requests.state.value),
    Spacecraft: stateOf(fleet.state.value),
  }));
  const retry: Readonly<Partial<Record<Group, () => void>>> = {
    Alarms: alarms.retry,
    Requests: requests.refetch,
    Spacecraft: fleet.refetch,
  };
  const pending = computed(() => Object.values(sources.value).includes("loading"));
  return { items, sources, retry, pending, alarmsTruncated: alarms.truncated };
}
