<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import type { SpacecraftId } from "@/api/index.ts";
import { computed, onScopeDispose } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { throttle } from "@/features/fleet/index.ts";
import { fetchHistory } from "./api.ts";
import { rangeWindow, toSeries } from "./model.ts";
import { sparkPoints } from "./sisters.ts";

/** B4 row sparkline: 80×24, the point's last 6 h on that sister, in the row's state (aria-hidden). */
const props = defineProps<{
  missionId: MissionId;
  spacecraftId: SpacecraftId;
  pointId: string;
  tone: "crit" | "caution";
}>();
const key = computed(() => `${props.missionId}|${props.spacecraftId}|${props.pointId}`);
const history = useRemoteQuery(key, (_k, signal) => {
  const w = rangeWindow("6h", new Date());
  return fetchHistory(
    props.missionId,
    props.pointId,
    props.spacecraftId,
    { from: new Date(w.from), to: new Date(w.to) },
    signal,
  );
});
const slow = throttle(history.refetch, 30_000);
useMissionInvalidation(
  computed(() => props.missionId),
  ["telemetry"],
  slow.call,
);
onScopeDispose(slow.cancel);
const points = computed(() =>
  history.state.value.status === "ready" ? sparkPoints(toSeries(history.state.value.value)) : null,
);
</script>

<template>
  <svg viewBox="0 0 80 24" class="h-6 w-20 flex-none" aria-hidden="true">
    <polyline
      v-if="points"
      :points="points"
      fill="none"
      stroke-width="1.25"
      vector-effect="non-scaling-stroke"
      :class="tone === 'crit' ? 'stroke-crit' : 'stroke-caution'"
    />
  </svg>
</template>
