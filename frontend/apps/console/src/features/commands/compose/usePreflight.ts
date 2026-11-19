import type { MissionId } from "@/api/index.ts";
import { computed, onScopeDispose, shallowRef, watch, type Ref } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { fetchPreflight, type Draft } from "../groups/api.ts";

/** Typing settles this long before the server re-checks (Command.md C3: re-run on any change). */
export const PREFLIGHT_DEBOUNCE_MS = 400;

type Settled = Readonly<{ json: string; draft: Draft }>;

/**
 * Server preflight (M18) for the current draft. `checking` is true until the result answers the
 * draft on screen, so a stale digest is never submitted. Queue and booking changes re-check.
 */
export function usePreflight(missionId: Ref<MissionId>, draft: Ref<Draft | null>) {
  const json = computed(() => (draft.value ? JSON.stringify(draft.value) : null));
  const settled = shallowRef<Settled | null>(null);
  let timer: ReturnType<typeof setTimeout> | undefined;
  watch(
    json,
    (next) => {
      clearTimeout(timer);
      const current = draft.value;
      if (next === null || current === null) {
        settled.value = null;
        return;
      }
      const commit = () => (settled.value = { json: next, draft: current });
      if (settled.value === null) commit();
      else timer = setTimeout(commit, PREFLIGHT_DEBOUNCE_MS);
    },
    { immediate: true },
  );
  onScopeDispose(() => clearTimeout(timer));

  const query = useRemoteQuery(settled, (s, signal) =>
    fetchPreflight(missionId.value, s.draft, signal),
  );
  const missionRef = computed<MissionId | null>(() => missionId.value);
  useMissionInvalidation(missionRef, ["commanding", "contacts", "catalog"], query.refetch);

  const checking = computed(
    () =>
      json.value !== null &&
      (settled.value?.json !== json.value || query.state.value.status === "loading"),
  );
  /** The preflight that answers exactly the draft on screen, or null. */
  const current = computed(() =>
    !checking.value && query.state.value.status === "ready" ? query.state.value.value : null,
  );
  return { state: query.state, checking, current, refetch: query.refetch };
}
