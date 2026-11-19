<script setup lang="ts">
import type { RuntimeRow } from "./api.ts";

/** A runtime row's Technical details (Admin.md): the failure message and node/process facts. */
defineProps<{ row: RuntimeRow }>();
</script>

<template>
  <details
    v-if="row.technical.length > 0 || row.runtime?.failure_message"
    class="text-sm text-text-3"
  >
    <summary class="cursor-pointer">Technical details</summary>
    <p v-if="row.runtime?.failure_message" class="m-0 font-mono text-xs">
      {{ row.runtime.failure_message }}
    </p>
    <p v-for="t in row.technical" :key="t.label" class="m-0 font-mono text-xs">
      {{ t.label }}: {{ t.value }}
    </p>
  </details>
</template>
