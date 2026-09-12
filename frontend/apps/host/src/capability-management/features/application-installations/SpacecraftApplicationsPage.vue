<script setup lang="ts">
import { pageContentAttrs } from "@cadence/ui/page-chrome";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import { installationBreadcrumbs } from "./breadcrumbs";
import SpacecraftApplications from "./SpacecraftApplications.vue";

import type { ApplicationEvent, SpacecraftPresentation } from "./contracts";

const props = defineProps<{ presentation: SpacecraftPresentation; disabled?: boolean }>();

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
      <template #actions
        ><a v-bind="props.presentation.header.actions.readiness.attrs">
          {{ props.presentation.header.actions.readiness.text }}
        </a></template
      >
    </CadencePageHeading>

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
