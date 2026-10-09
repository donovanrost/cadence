<script setup lang="ts">
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import type { VersionChange } from "./contracts";

defineProps<{ changes: readonly VersionChange[] }>();
const icon = {
  added: "hero-plus-circle",
  removed: "hero-minus-circle",
  changed: "hero-pencil-square",
} as const;
const tone = { added: "text-success", removed: "text-error", changed: "text-warning" } as const;
</script>

<template>
  <ul v-if="changes.length" class="space-y-1.5">
    <li v-for="(change, index) in changes" :key="index" class="flex gap-2 text-sm">
      <span :class="tone[change.kind]"><CadenceIcon :name="icon[change.kind]" /></span>
      <span class="min-w-0">
        {{ change.label }}
        <span v-if="change.detail" class="block break-words font-mono text-xs text-base-content/60">
          {{ change.detail }}
        </span>
      </span>
    </li>
  </ul>
  <p v-else class="text-sm text-base-content/70">No changes.</p>
</template>
