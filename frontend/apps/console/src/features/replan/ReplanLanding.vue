<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed } from "vue";
import { useRemoteQuery, type RemoteState } from "@/api";
import { fetchPlans, type Availability } from "@/features/scheduling/index.ts";
import { fetchStations } from "@/features/stations/index.ts";
import { ApEmptyState, ApPanel, useNow } from "@/ui";
import { replanDays, replanSources } from "./sources.ts";

/** R1 · Re-plan landing (ux §7 #6): what can be re-planned, each linking to its re-plan. */
const props = defineProps<{ missionId: MissionId; availability: RemoteState<Availability> }>();
const now = useNow();
const days = computed(() => replanDays(now.value));
const today = useRemoteQuery(
  () => ({ missionId: props.missionId, day: days.value[0] }),
  (k, signal) => fetchPlans(k.missionId, k.day, signal),
);
const tomorrow = useRemoteQuery(
  () => ({ missionId: props.missionId, day: days.value[1] }),
  (k, signal) => fetchPlans(k.missionId, k.day, signal),
);
const stations = useRemoteQuery(() => props.missionId, fetchStations);
const nameOf = (id: string) =>
  (stations.state.value.status === "ready"
    ? stations.state.value.value.find((s) => s.id === id)?.display_name
    : undefined) ?? "A station";
const states = computed(() => [today.state.value, tomorrow.state.value, props.availability]);
const loading = computed(() => states.value.some((s) => s.status === "loading"));
const failed = computed(() => states.value.some((s) => s.status === "failed"));
const sources = computed(() =>
  replanSources(
    [
      { day: days.value[0], st: today.state.value },
      { day: days.value[1], st: tomorrow.state.value },
    ].map(({ day, st }) => ({ day, plans: st.status === "ready" ? st.value.plans : [] })),
    props.availability.status === "ready" ? props.availability.value : null,
    nameOf,
  ),
);
</script>

<template>
  <ApPanel index="R1" title="What can be re-planned" flush>
    <p v-if="loading" class="m-0 px-4 py-3 font-mono text-xs text-text-3 uppercase">Loading…</p>
    <ul v-else-if="sources.length > 0" class="m-0 flex list-none flex-col p-0">
      <li
        v-for="s in sources"
        :key="s.key"
        class="border-b border-hairline px-4 py-2.5 last:border-b-0"
      >
        <RouterLink :to="s.to" class="text-md text-readout hover:underline">{{
          s.label
        }}</RouterLink>
      </li>
    </ul>
    <ApEmptyState
      v-else
      :headline="failed ? 'Couldn\'t check every source' : 'Nothing needs a re-plan.'"
      :sentence="
        failed
          ? 'Some plans or station states didn\'t load. Check Plan and Contacts.'
          : 'No plan for today or tomorrow has rejected or failed bookings, and no station is down.'
      "
    >
      <div class="flex gap-4 text-md">
        <RouterLink :to="{ name: 'ops.contacts.plan' }" class="text-readout hover:underline"
          >Open Plan</RouterLink
        >
        <RouterLink :to="{ name: 'ops.contacts' }" class="text-readout hover:underline"
          >Open Contacts</RouterLink
        >
      </div>
    </ApEmptyState>
  </ApPanel>
</template>
