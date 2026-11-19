<script setup lang="ts">
import type { PlatformAuditEvent } from "./api.ts";

/**
 * An audit row's What: the server's sentence and its target, or "Unreadable entry" with whatever
 * text the row still had under Technical details, so it can be reported (ux, lead 11-13).
 */
defineProps<{
  event: PlatformAuditEvent | null;
  raw: readonly Readonly<{ label: string; value: string }>[];
}>();
</script>

<template>
  <template v-if="!event">
    <span class="text-text-3">Unreadable entry</span>
    <details v-if="raw.length > 0" class="mt-1">
      <summary class="ap-label cursor-pointer">Technical details</summary>
      <ul class="m-0 mt-1 flex list-none flex-col gap-0.5 p-0 font-mono text-xs text-text-3">
        <li v-for="f in raw" :key="f.label">{{ f.label }}: {{ f.value }}</li>
      </ul>
    </details>
  </template>
  <template v-else
    >{{ event.action
    }}<span v-if="event.target?.label" class="text-text-3">
      · {{ event.target.label }}</span
    ></template
  >
</template>
