<script setup lang="ts">
import { computed } from "vue";
import DetailFrame from "../../shared/DetailFrame.vue";
import type { Detail } from "../../shared/read-contracts";
import type { TransportDetails } from "./read-contracts";
const props = defineProps<{ page: Detail<TransportDetails> }>();
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
  <DetailFrame
    id="comms-transports-detail"
    :navigation="page.navigation"
    :title="page.data.display_name"
    :subject-id="page.data.id"
    :list-href="page.data.list_href"
    :facts="facts"
  >
  </DetailFrame>
</template>
