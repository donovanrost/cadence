<script setup lang="ts">
import type { Dependent } from "./dependents.ts";

/** U42: each derived point a retire would break, linked to its definition (mono; 5, then "and N more"). */
defineProps<{ points: readonly Dependent[] }>();
</script>

<template>
  <p v-if="points.length > 0" class="m-0 border-t border-hairline px-4 py-2.5 text-sm text-text-2">
    Open in Derived telemetry:
    <template v-for="(p, i) in points.slice(0, 5)" :key="p.definition_id">
      <template v-if="i > 0"> · </template>
      <RouterLink
        :to="{
          name: 'setup.app',
          params: { appKey: 'derived_telemetry', surface: 'manage' },
          query: { definition: p.definition_id },
        }"
        class="font-mono text-primary no-underline hover:underline"
        >{{ p.point_id }}</RouterLink
      >
    </template>
    <span v-if="points.length > 5" class="text-text-3"> and {{ points.length - 5 }} more</span>
  </p>
</template>
