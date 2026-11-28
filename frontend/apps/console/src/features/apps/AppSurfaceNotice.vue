<script setup lang="ts">
import { ApButton, ApCallout } from "@/ui";
import type { HostRefusal } from "./surfaces.ts";

/** The host's notices (ux AppSurfaces.md States): not installed, no pages, read-only. */
defineProps<{
  appName: string;
  missionName: string;
  refusal: HostRefusal;
  noSurface: boolean;
  readOnly: boolean;
}>();
</script>

<template>
  <ApCallout v-if="refusal === 'not_installed'" tone="off">
    {{ appName }} isn't installed on {{ missionName }}.
    <template #action
      ><ApButton size="compact" :to="{ name: 'setup.apps' }">Install in Apps</ApButton></template
    >
  </ApCallout>
  <ApCallout v-else-if="refusal === 'unknown'" tone="caution"
    >This app or page doesn't exist on {{ missionName }}.</ApCallout
  >
  <ApCallout v-else-if="noSurface" tone="info"
    >{{ appName }} has no pages to set up here.</ApCallout
  >
  <p v-if="readOnly && !refusal" class="m-0 text-sm text-text-3">
    Org admins change app configuration.
  </p>
</template>
