import type { MissionId } from "@/api/index.ts";
import { computed, watch, type Ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { describeApiError, useRemoteQuery } from "@/api/index.ts";
import { fetchEvent, type MissionEvent } from "./api.ts";

/**
 * The selected event, from `?event=<id>` (ux decisions U71 A8, api a87bee73d). It's looked up in the
 * shown list. Otherwise (a permalink, or the event left the window) it's read by id once the list
 * has loaded, and the window is centred on it if it falls outside. A 404 reads 'not found'.
 */
export function useEventSelection(
  options: Readonly<{
    missionId: Readonly<Ref<MissionId>>;
    shown: Readonly<Ref<readonly MissionEvent[] | null>>;
    /** The events read's window (ms), null while loading. */
    window: Readonly<Ref<{ from: number; to: number } | null>>;
    centreOn: (at: number) => void;
  }>,
) {
  const route = useRoute();
  const router = useRouter();
  const selectedId = computed(() =>
    typeof route.query["event"] === "string" ? route.query["event"] : null,
  );
  const inList = computed(
    () => options.shown.value?.find((e) => e.id === selectedId.value) ?? null,
  );
  const lookup = useRemoteQuery(
    computed(() =>
      selectedId.value && options.shown.value !== null && !inList.value
        ? { m: options.missionId.value, id: selectedId.value }
        : null,
    ),
    (k, signal) => fetchEvent(k.m, k.id, signal),
  );
  const fetched = computed(() =>
    lookup.state.value.status === "ready" ? lookup.state.value.value : null,
  );
  const notFound = computed(
    () => lookup.state.value.status === "failed" && lookup.state.value.error.kind === "not_found",
  );
  /** Any other failure says so, with Retry (fe-ops' review). */
  const loadError = computed(() =>
    lookup.state.value.status === "failed" && lookup.state.value.error.kind !== "not_found"
      ? describeApiError(lookup.state.value.error)
      : null,
  );
  watch(fetched, (e) => {
    const w = options.window.value;
    if (!e || !w) return;
    const at = Date.parse(e.at);
    if (at < w.from || at > w.to) options.centreOn(at);
  });
  function setEvent(id: string | null) {
    const { event: _drop, ...rest } = route.query;
    router
      .replace({ query: id === null ? rest : { ...rest, event: id } })
      .catch((e: unknown) => console.error("Navigation failed", e));
  }
  return {
    selectedId,
    event: computed(() => inList.value ?? fetched.value),
    notFound,
    loadError,
    retry: () => lookup.refetch(),
    /** The row's time button: selects it, or clears when it's already selected (aria-pressed). */
    toggle: (id: string) => setEvent(selectedId.value === id ? null : id),
    clear: () => setEvent(null),
  };
}
