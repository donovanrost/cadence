import { computed, onBeforeUnmount, ref, type Ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useRemoteQuery, type MissionId, type SpacecraftId } from "@/api/index.ts";
import { fetchSample } from "./api.ts";

/**
 * ux U80 / lead: the Telemetry tab's `?sample=<id>` (and `?received=<ISO>`, which makes the read
 * exact). The point is the focused one, so a cold load of the permalink reopens the same aside;
 * without `received`, `at` narrows api's search to ±60 s (it may answer ambiguous). Closing drops
 * `sample` and `received`; `at` stays, so the plot keeps ringing the time.
 */
export function useSample(
  missionId: Ref<MissionId>,
  spacecraftId: Ref<SpacecraftId>,
  pointId: Ref<string | null>,
) {
  const route = useRoute();
  const router = useRouter();
  const text = (v: unknown) => (typeof v === "string" && v ? v : null);
  const sampleId = computed(() => text(route.query.sample));
  const received = computed(() => {
    const v = text(route.query.received);
    return v !== null && !Number.isNaN(Date.parse(v)) ? v : null;
  });
  const at = computed(() => {
    const v = text(route.query.at);
    return v !== null && !Number.isNaN(Date.parse(v)) ? v : null;
  });
  const read = useRemoteQuery(
    computed(() =>
      sampleId.value && pointId.value
        ? {
            m: missionId.value,
            k: {
              sampleId: sampleId.value,
              pointId: pointId.value,
              spacecraftId: spacecraftId.value,
              receiptTime: received.value,
              at: at.value,
            },
          }
        : null,
    ),
    (key, signal) => fetchSample(key.m, key.k, signal),
  );
  const open = computed(() => sampleId.value !== null && pointId.value !== null);
  function close(): Promise<unknown> {
    return router
      .replace({ query: { ...route.query, sample: undefined, received: undefined } })
      .catch((e: unknown) => console.error("Navigation failed", e));
  }
  return { open, read, close };
}

/** True from 1100px (the console breakpoint), where the aside sits in T1's column (U80). */
export function useConsoleWide(): Readonly<Ref<boolean>> {
  const query =
    typeof window.matchMedia === "function" ? window.matchMedia("(min-width: 68.75rem)") : null;
  const wide = ref(query?.matches ?? true);
  const on = (e: MediaQueryListEvent) => (wide.value = e.matches);
  query?.addEventListener("change", on);
  onBeforeUnmount(() => query?.removeEventListener("change", on));
  return wide;
}
