<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { formatCount, formatDuration, useNow, ApPageHeader } from "@/ui";
import { useStationCodes } from "@/features/contacts/useStationCodes.ts";
import type { Fleet } from "@/features/fleet/index.ts";
import { fetchAvailability } from "@/features/scheduling/index.ts";
import { worstStationIssue } from "./stationMeta.ts";

/** Header: computed situation h1 + freshness meta. Unknown parts are omitted, never guessed. */
const props = defineProps<{
  missionId: MissionId;
  missionName: string;
  headline: string;
  fleet: Fleet | null;
}>();
const now = useNow();
/** S7 station availability for the worst station issue (Now.md Header). */
const mission = computed(() => props.missionId);
const availability = useRemoteQuery(mission, (id, signal) => fetchAvailability(id, signal));
useMissionInvalidation(mission, ["stations"], availability.refetch);
const stations = useStationCodes(mission);
const stationIssue = computed(() =>
  worstStationIssue(
    availability.state.value.status === "ready" ? availability.state.value.value : null,
    (id) => stations.byId(id)?.code ?? null,
    now.value,
  ),
);

const meta = computed(() => {
  const fleet = props.fleet;
  if (!fleet) return "";
  const parts = [`TLM fresh ${formatCount(fleet.counts.fresh)}/${formatCount(fleet.counts.total)}`];
  if (fleet.last_received_at) {
    const age = (now.value.getTime() - Date.parse(fleet.last_received_at)) / 1000;
    parts.push(`last pkt ${formatDuration(age)}`);
  }
  if (stationIssue.value) parts.push(stationIssue.value.line);
  return parts.join(" · ");
});
</script>

<template>
  <ApPageHeader :label="`${missionName} · constellation status`" :title="headline">
    <p
      v-if="meta"
      class="m-0 font-mono text-sm text-text-3 uppercase"
      :title="stationIssue && stationIssue.all.length > 1 ? stationIssue.all.join('\n') : undefined"
    >
      {{ meta }}
    </p>
  </ApPageHeader>
</template>
