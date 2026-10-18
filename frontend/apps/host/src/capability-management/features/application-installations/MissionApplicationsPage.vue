<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import MissionApplications from "./MissionApplications.vue";

import type { ApplicationEvent, MissionPresentation } from "./contracts";

const props = defineProps<{ presentation: MissionPresentation; disabled?: boolean }>();

const emit = defineEmits<{
  install: [payload: ApplicationEvent];
  disable: [payload: ApplicationEvent];
  uninstall: [payload: ApplicationEvent];
}>();
useManagementHeader("/missions/:mission_id/applications", () => ({
  description: props.presentation.header.subtitle.text,
}));
</script>

<template>
  <div v-bind="pageContentAttrs(props.presentation.root.attrs)">
    <div v-bind="props.presentation.applications_component.attrs">
      <MissionApplications
        :applications="props.presentation.applications_component.props.applications"
        :disabled="props.disabled"
        @install="emit('install', $event)"
        @disable="emit('disable', $event)"
        @uninstall="emit('uninstall', $event)"
      />
    </div>
  </div>
</template>
