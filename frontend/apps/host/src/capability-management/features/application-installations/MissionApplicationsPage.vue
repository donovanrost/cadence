<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import { installationBreadcrumbs } from "./breadcrumbs";
import MissionApplications from "./MissionApplications.vue";

import type { ApplicationEvent, MissionPresentation } from "./contracts";

const props = defineProps<{ presentation: MissionPresentation; disabled?: boolean }>();

const emit = defineEmits<{
  install: [payload: ApplicationEvent];
  disable: [payload: ApplicationEvent];
  uninstall: [payload: ApplicationEvent];
}>();
</script>

<template>
  <div v-bind="pageContentAttrs(props.presentation.root.attrs)">
    <CadencePageHeading
      :breadcrumbs="installationBreadcrumbs(props.presentation.header.breadcrumbs)"
    >
      <template #title>{{ props.presentation.header.title.text }}</template>
      <template #description>{{ props.presentation.header.subtitle.text }}</template>
    </CadencePageHeading>

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
