import type { MissionId } from "@/api/index.ts";
import { computed, type Ref } from "vue";
import { useRemoteQuery } from "@/api";
import { fetchPasses, type Pass } from "@/features/contacts/index.ts";
import { useMissionInvalidation } from "@/live";

/**
 * U31: the day's passes with an open or acknowledged pass-resolution conflict (DECISIONS #54),
 * from the passes read (each row carries its `attention`; null for viewers who can't operate).
 */
export function usePassResolutions(
  missionId: Readonly<Ref<MissionId>>,
  day: Readonly<Ref<string>>,
) {
  const passes = useRemoteQuery(
    () => ({ m: missionId.value, d: day.value }),
    (k, signal) => {
      const from = new Date(`${k.d}T00:00:00Z`);
      return fetchPasses(k.m, { from, to: new Date(from.getTime() + 86_400_000) }, signal);
    },
  );
  useMissionInvalidation(missionId, ["attention", "contacts"], passes.refetch);
  return computed<Pass[]>(() =>
    passes.state.value.status === "ready"
      ? passes.state.value.value.passes
          // U86: a top item this console can't read is still open; the callout counts it.
          .filter((p) => p.attention || p.attention_unshown)
          // U21: acknowledged isn't resolved; it stays, sorted last, soonest AOS first within each.
          .sort(
            (a, b) =>
              Number(a.attention?.state === "acknowledged") -
                Number(b.attention?.state === "acknowledged") ||
              a.starts_at.localeCompare(b.starts_at),
          )
      : [],
  );
}
