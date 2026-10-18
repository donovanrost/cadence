<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import { serverHref } from "@cadence/plugin-sdk/routes";
import SpacecraftApplications from "./SpacecraftApplications.vue";

import type { ApplicationEvent, SpacecraftPresentation } from "./contracts";

const props = defineProps<{ presentation: SpacecraftPresentation; disabled?: boolean }>();

const emit = defineEmits<{
  install: [payload: ApplicationEvent];
  disable: [payload: ApplicationEvent];
  uninstall: [payload: ApplicationEvent];
}>();
useManagementHeader("/missions/:mission_id/spacecraft/:spacecraft_id/applications", () => ({
  title: props.presentation.header.title.text,
  description: props.presentation.header.subtitle.text,
  actions: [
    {
      id: "spacecraft-applications-readiness",
      label: props.presentation.header.actions.readiness.text,
      icon: "hero-check-badge",
      href: serverHref(String(props.presentation.header.actions.readiness.attrs.href)),
    },
  ],
}));
</script>

<template>
  <div v-bind="pageContentAttrs(props.presentation.root.attrs)">
    <div v-bind="props.presentation.component.attrs">
      <SpacecraftApplications
        :profile="props.presentation.profile"
        :applications="props.presentation.applications"
        :disabled="props.disabled"
        @install="emit('install', $event)"
        @disable="emit('disable', $event)"
        @uninstall="emit('uninstall', $event)"
      />
    </div>
  </div>
</template>
