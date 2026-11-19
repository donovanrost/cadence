<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import type { RouteLocationRaw } from "vue-router";
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { fetchProfileDetail } from "@/features/profiles/index.ts";
import { ApCallout, ApRemote } from "@/ui";
import { routingSummary } from "./routing.ts";

/** Step 03 routing (AddSpacecraft.md): the profile's rules generate the new spacecraft's routes. */
const props = defineProps<{ missionId: MissionId; profileId: string; count: number }>();
const detail = useRemoteQuery(
  () => ({ missionId: props.missionId, profileId: props.profileId }),
  fetchProfileDetail,
);
const summary = computed(() =>
  detail.state.value.status === "ready"
    ? routingSummary(detail.state.value.value, props.count)
    : null,
);
const routingTab = computed((): RouteLocationRaw => ({
  name: "setup.profile",
  params: { profileId: props.profileId, section: "routing" },
}));
</script>

<template>
  <ApRemote
    :state="detail.state.value"
    loading-label="Loading the profile's routing…"
    @retry="detail.refetch"
  >
    <ApCallout v-if="summary?.kind === 'per_spacecraft'" tone="info"
      >This profile's spacecraft set their own routing, so these get none from it. Add their routes
      in Comms &amp; routing after creating them.</ApCallout
    >
    <ApCallout v-else-if="summary?.kind === 'none'" tone="caution"
      >This profile has no routing rules, so these spacecraft get no routes.
      <RouterLink :to="routingTab" class="text-readout hover:underline">Add a rule</RouterLink>
      first if they need contacts.</ApCallout
    >
    <div v-else-if="summary" class="flex flex-col gap-1">
      <span class="ap-label">Routing</span>
      <span v-for="line in summary.lines" :key="line" class="font-mono text-md text-readout">{{
        line
      }}</span>
      <span class="text-md text-text-2">{{ summary.total }}, made when the batch is applied.</span>
    </div>
  </ApRemote>
</template>
