import { computed, type Ref } from "vue";
import { useRemoteQuery, type MissionId, type RemoteState } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import { passStatus } from "./gantt.ts";
import type { Pass, Passes } from "./api.ts";
import { fetchPassOrContact, isHandStarted } from "./handStarted.ts";

/**
 * D2's pass (Contacts Live): the pass named in `?contact=` (read on its own when it's outside the
 * window, U31), else the next AOS fleet-wide among the shown passes. ?contact= may carry a
 * reservation, scheduled or realized contact id (U78); the fetched row keeps its own id. A
 * hand-started contact comes back as `handStarted` and never as the selected pass.
 */
export function useSelectedPass(
  missionId: Ref<MissionId>,
  passes: Readonly<{ state: Ref<RemoteState<Passes>>; refetch: () => void }>,
  shown: Ref<readonly Pass[]>,
  selectedId: Ref<string | null>,
  byId: Ref<ReadonlyMap<string, FleetSpacecraft>>,
  now: Ref<Date>,
) {
  const all = computed(() =>
    passes.state.value.status === "ready" ? passes.state.value.value.passes : [],
  );
  /** A pass named in the URL but outside the window (Review from Now, U31) is read on its own. */
  const outsideKey = computed(() => {
    const id = selectedId.value;
    if (id === null || passes.state.value.status !== "ready") return null;
    return all.value.some((p) => p.id === id) ? null : { m: missionId.value, id };
  });
  const outside = useRemoteQuery(outsideKey, (k, signal) => fetchPassOrContact(k.m, k.id, signal));
  useMissionInvalidation(missionId, ["contacts", "attention"], outside.refetch);
  const outsideRow = computed(() =>
    outside.state.value.status === "ready" ? outside.state.value.value : null,
  );
  const outsidePass = computed(() => {
    const row = outsideRow.value;
    return row && !isHandStarted(row) ? row : null;
  });
  /** U78: ?contact= named a hand-started contact; the drawer shows its record alone. */
  const handStarted = computed(() => {
    const row = outsideRow.value;
    return row && isHandStarted(row) ? row : null;
  });
  function refetch() {
    passes.refetch();
    if (outsideKey.value !== null) outside.refetch();
  }
  const selected = computed(() => {
    const t = now.value.getTime();
    const named = all.value.find((p) => p.id === selectedId.value) ?? outsidePass.value;
    if (named) return named;
    // A pass named in the URL that hasn't resolved yet (or is a hand-started contact): show
    // that, not another pass (qa).
    if (selectedId.value !== null) return null;
    return (
      shown.value.find((p) => Date.parse(p.starts_at) > t && passStatus(p, t) === "scheduled") ??
      null
    );
  });
  /** The URL's pass is still being read: the window first, then the pass on its own. */
  const loading = computed(
    () =>
      selectedId.value !== null &&
      selected.value === null &&
      (passes.state.value.status !== "ready" ||
        (outsideKey.value !== null && outside.state.value.status === "loading")),
  );
  const missing = computed(
    () =>
      selectedId.value !== null &&
      selected.value === null &&
      handStarted.value === null &&
      !loading.value &&
      outside.state.value.status === "failed",
  );
  /** D2 identity: the fleet row (has state) else the pass's own {name, scid}. */
  const spacecraft = computed(() => {
    const p = selected.value;
    if (!p) return null;
    const known = p.spacecraft_id ? byId.value.get(p.spacecraft_id) : undefined;
    if (known) return known;
    // A deleted spacecraft keeps its pass rows with a null name (contacts.md).
    return p.spacecraft?.scid != null
      ? { name: p.spacecraft.name ?? "Deleted spacecraft", scid: p.spacecraft.scid }
      : null;
  });
  return { selected, handStarted, loading, missing, spacecraft, refetch };
}
