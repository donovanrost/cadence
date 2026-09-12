<script setup lang="ts">
import { computed } from "vue";
import DetailFrame from "../../shared/DetailFrame.vue";
import type { Detail } from "../../shared/read-contracts";
import type { GroundStationDetails } from "./read-contracts";
const props = defineProps<{ page: Detail<GroundStationDetails> }>();
const facts = computed(() => [
  { label: "Lifecycle", value: props.page.data.lifecycle_state },
  { label: "Provider", value: props.page.data.provider },
  { label: "Region", value: props.page.data.region },
]);
</script>
<template>
  <DetailFrame
    id="comms-ground-stations-detail"
    :navigation="page.navigation"
    :title="page.data.display_name"
    :subject-id="page.data.id"
    :list-href="page.data.list_href"
    :facts="facts"
  >
    <template #actions
      ><a
        id="comms-ground-station-edit"
        :href="page.data.edit_href"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="btn btn-primary btn-sm"
        >Edit station</a
      ></template
    >
  </DetailFrame>
</template>
