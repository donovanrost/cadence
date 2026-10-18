<script setup lang="ts">
import { computed } from "vue";
import LegacyDestination from "../../shared/LegacyDestination.vue";
import { directoryDestination } from "./destination";

defineOptions({ inheritAttrs: false });
const props = defineProps<{ model: unknown; organizationId: unknown; missionId: unknown }>();
const href = computed(() =>
  directoryDestination(props.model, props.organizationId, props.missionId),
);
</script>

<template>
  <LegacyDestination
    id="dashboard-directory-destination"
    title="Dashboard Directory"
    :href="href"
  />
</template>
