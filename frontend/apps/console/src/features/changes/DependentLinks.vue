<script setup lang="ts">
import { MONITORING_EDITS_PENDING } from "@/features/telemetry/index.ts";
import type { Dependent } from "./dependents.ts";

/** U42: each derived point a retire would break (mono; 5, then "and N more"), and where it's edited. */
defineProps<{ points: readonly Dependent[] }>();
</script>

<template>
  <p v-if="points.length > 0" class="m-0 border-t border-hairline px-4 py-2.5 text-sm text-text-2">
    Derived points that use it:
    <template v-for="(p, i) in points.slice(0, 5)" :key="p.definition_id">
      <template v-if="i > 0"> · </template>
      <span class="font-mono">{{ p.point_id }}</span>
    </template>
    <span v-if="points.length > 5" class="text-text-3"> and {{ points.length - 5 }} more</span>.
    {{ MONITORING_EDITS_PENDING }}
  </p>
</template>
