<script setup lang="ts">
import type { VersionChange } from "./contracts.ts";

/** Server-made change labels (VersionDiff), one per line: + added, − removed, ~ changed. */
defineProps<{ changes: readonly VersionChange[]; empty?: string | undefined }>();
const sign = { added: "+", removed: "−", changed: "~" } as const;
</script>

<template>
  <ul v-if="changes.length" class="m-0 flex list-none flex-col gap-1 p-0 text-md">
    <li v-for="(c, i) in changes" :key="i" class="flex gap-2">
      <span class="w-3 flex-none font-mono text-text-4" aria-hidden="true">{{ sign[c.kind] }}</span>
      <span class="min-w-0">
        <span class="text-readout">{{ c.label }}</span>
        <span v-if="c.detail" class="text-text-3"> · {{ c.detail }}</span>
      </span>
    </li>
  </ul>
  <p v-else class="m-0 text-sm text-text-3">{{ empty ?? "No changes." }}</p>
</template>
