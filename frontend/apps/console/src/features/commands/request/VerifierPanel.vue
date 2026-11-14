<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed } from "vue";
import { ApPanel } from "@/ui";
import { perPoint, seriesMeta } from "../groups/series.ts";
import type { VerifierSeriesQuery } from "./useVerifierSeries.ts";
import VerifierPlot from "./VerifierPlot.vue";
import VerifierPointPlot from "./VerifierPointPlot.vue";

/**
 * U2 · Verifier (CommandFlow C3, M26). UplinkView owns the default read (N Needs you shares it).
 * U51: when targets watch different verifier points, one plot per point, each with its targets.
 */
const props = defineProps<{
  series: VerifierSeriesQuery;
  missionId: MissionId;
  groupId: string;
  nameOf: (spacecraftId: string) => string;
}>();
const ready = computed(() => props.series.ready.value);
const points = computed(() => (perPoint(ready.value) ? (ready.value?.points ?? []) : []));
</script>

<template>
  <!-- The header tallies the default point; with several, each plot's caption says whose it is. -->
  <ApPanel
    index="U2"
    title="Verifier"
    :meta="ready && !points.length ? seriesMeta(ready) : undefined"
    flush
  >
    <template v-if="points.length">
      <VerifierPointPlot
        v-for="p in points"
        :key="`${p.position}:${p.point_id}`"
        :mission-id="missionId"
        :group-id="groupId"
        :point="p"
        :name-of="nameOf"
        class="border-t border-hairline first:border-t-0"
      />
    </template>
    <VerifierPlot v-else :state="series.state.value" @retry="series.refetch()" />
  </ApPanel>
</template>
