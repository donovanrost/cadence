<script setup lang="ts">
import { computed } from "vue";
import LegacyDestination from "../../shared/LegacyDestination.vue";
import { creationDestination } from "./destination";

defineOptions({ inheritAttrs: false });
const props = defineProps<{ model: unknown; organizationId: unknown; missionId: unknown }>();
const target = computed(() =>
  creationDestination(props.model, props.organizationId, props.missionId),
);
</script>

<template>
  <LegacyDestination
    id="dashboard-creation-destination"
    :title="target?.title ?? 'Dashboard creation'"
    :href="target?.href ?? null"
  />
</template>
