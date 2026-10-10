<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import CommsOverview from "./CommsOverview.vue";
import type { CommsOverviewPresentation } from "./contracts";

const props = defineProps<{ presentation: CommsOverviewPresentation }>();
useManagementHeader("/missions/:mission_id/comms", {
  description: "Saved transports, routing and ground stations for this mission's traffic.",
});
</script>

<template>
  <div v-bind="pageContentAttrs(props.presentation.root.attrs)">
    <CommsOverview :overview="props.presentation.overview" />
  </div>
</template>
