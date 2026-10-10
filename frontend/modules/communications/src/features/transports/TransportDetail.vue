<script setup lang="ts">
import { computed } from "vue";
import DetailFrame from "../../shared/DetailFrame.vue";
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import type { Detail } from "../../shared/read-contracts";
import type { TransportDetails } from "./read-contracts";
const props = defineProps<{ page: Detail<TransportDetails> }>();
useManagementHeader("/missions/:mission_id/comms/transports/:transport_id", () => ({
  title: props.page.data.display_name,
  identifier: props.page.data.id,
}));
const facts = computed(() => [
  { label: "Version", value: props.page.data.version },
  { label: "Lifecycle", value: props.page.data.lifecycle_state },
  { label: "Origin", value: props.page.data.origin },
  { label: "Transport kind", value: props.page.data.transport_kind },
  { label: "Direction capability", value: props.page.data.direction_capability },
  { label: "Provider managed", value: props.page.data.provider_managed ? "Yes" : "No" },
]);
</script>
<template>
  <DetailFrame id="comms-transports-detail" :facts="facts" />
</template>
