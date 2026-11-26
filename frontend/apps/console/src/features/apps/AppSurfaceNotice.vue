<script setup lang="ts">
import { ApButton, ApCallout } from "@/ui";
import type { SaveOutcome } from "./saveOutcome.ts";
import type { HostRefusal } from "./surfaces.ts";

/** The host's notices (ux AppSurfaces.md States): not installed, no pages, read-only, save results. */
defineProps<{
  appName: string;
  missionName: string;
  refusal: HostRefusal;
  noSurface: boolean;
  readOnly: boolean;
  outcome: SaveOutcome | null;
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
  <!-- A3 (#313, ux §10): a requested activation has one line, the status line's caution
    "Waiting for activation approval…", announced there; no nominal callout beside it. -->
  <ApCallout
    v-if="outcome && outcome.kind !== 'staged' && outcome.kind !== 'activation_requested'"
    tone="nominal"
    >{{ outcome.text }}</ApCallout
  >
</template>
