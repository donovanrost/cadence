<script setup lang="ts">
import type { Change } from "./shapes.ts";

/** A staged change's ops, expanded: action, kind, entity and the paths it touches. */
defineProps<{ change: Change }>();
</script>

<template>
  <ul class="m-0 list-none border-t border-hairline-faint bg-vacuum px-4 py-2.5 font-mono text-sm">
    <li v-for="op in change.ops" :key="op.id" class="py-0.5 text-text-2">
      <span class="text-text-4">{{ op.action }} {{ op.kind }}</span>
      {{ op.entity_id ?? "new"
      }}<template v-if="op.paths.length > 0"> · {{ op.paths.join(", ") }}</template>
    </li>
  </ul>
</template>
