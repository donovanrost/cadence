<script setup lang="ts">
import { computed } from "vue";
import DetailFrame from "../../shared/DetailFrame.vue";
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import { href } from "@cadence/plugin-sdk/routes";
import type { Detail, ReadContext } from "../../shared/read-contracts";
import type { GroundStationDetails } from "./read-contracts";
const props = defineProps<{ page: Detail<GroundStationDetails>; context: ReadContext }>();
useManagementHeader("/missions/:mission_id/comms/ground-stations/:ground_station_id", () => ({
  title: props.page.data.display_name,
  identifier: props.page.data.id,
  primary: {
    id: "edit",
    label: "Edit station",
    icon: "hero-pencil-square",
    href: href("/missions/:mission_id/comms/ground-stations/:ground_station_id/edit", {
      mission_id: props.context.missionId,
      ground_station_id: props.page.data.id,
    }),
  },
}));
const facts = computed(() => [
  { label: "Lifecycle", value: props.page.data.lifecycle_state },
  { label: "Provider", value: props.page.data.provider },
  { label: "Region", value: props.page.data.region },
]);
</script>
<template>
  <DetailFrame id="comms-ground-stations-detail" :facts="facts" />
</template>
