<script setup lang="ts">
import { computed } from "vue";
import DetailFrame from "../../shared/DetailFrame.vue";
import type { Detail } from "../../shared/read-contracts";
import type { RoutingDetails } from "./read-contracts";
const props = defineProps<{ page: Detail<RoutingDetails> }>();
const facts = computed(() => [
  { label: "Enabled", value: props.page.data.enabled ? "Yes" : "No" },
  { label: "Lifecycle", value: props.page.data.lifecycle_state },
  { label: "Spacecraft ID", value: props.page.data.spacecraft_id },
  { label: "Spacecraft", value: props.page.data.spacecraft_name },
  { label: "Purpose", value: props.page.data.purpose_label },
  { label: "Direction", value: props.page.data.direction },
  { label: "Transport ID", value: props.page.data.transport_id },
  { label: "Transport", value: props.page.data.transport_name },
  { label: "Pinned transport version", value: props.page.data.transport_version },
  { label: "Role", value: props.page.data.role },
]);
</script>
<template>
  <DetailFrame
    id="comms-routing-detail"
    :navigation="page.navigation"
    :title="page.data.display_name"
    :subject-id="page.data.id"
    :list-href="page.data.list_href"
    :facts="facts"
  >
  </DetailFrame>
</template>
