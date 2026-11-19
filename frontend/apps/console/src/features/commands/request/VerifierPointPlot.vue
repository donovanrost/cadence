<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { throttle } from "@/features/fleet/index.ts";
import { fetchVerifierSeries, pointCaption, type VerifierPoint } from "../groups/series.ts";
import VerifierPlot from "./VerifierPlot.vue";

/** U51: one point's plot, read with `?point=`, captioned with the targets that watch it. */
const props = defineProps<{
  missionId: MissionId;
  groupId: string;
  point: VerifierPoint;
  nameOf: (spacecraftId: string) => string;
}>();
const series = useRemoteQuery(
  computed(() => ({ m: props.missionId, g: props.groupId, p: props.point.point_id })),
  (k, signal) => fetchVerifierSeries(k.m, k.g, signal, k.p),
);
const missionId = computed(() => props.missionId);
useMissionInvalidation(missionId, ["commanding"], series.refetch);
const slow = throttle(series.refetch, 10_000);
useMissionInvalidation(missionId, ["telemetry"], slow.call);
</script>

<template>
  <VerifierPlot
    :state="series.state.value"
    :caption="pointCaption(point, nameOf)"
    @retry="series.refetch()"
  />
</template>
