<script setup lang="ts">
import { humanize } from "./actions.ts";
import type { RollbackPreview } from "./rollback.ts";

/** What the rollback does, one line per op (created after → removed, deleted → re-created, …). */
defineProps<{ ops: RollbackPreview["ops"] }>();
const verb: Readonly<Record<string, string>> = {
  create: "Re-create",
  update: "Change back",
  delete: "Remove",
  archive: "Archive",
};
</script>

<template>
  <ul class="m-0 flex list-none flex-col gap-1 p-0 text-sm">
    <li v-for="(op, i) in ops.slice(0, 20)" :key="i" class="flex flex-wrap gap-x-2">
      <span class="text-text-2">{{ verb[op.action] ?? humanize(op.action) }}</span>
      <span class="text-text-3">{{ humanize(op.kind).toLowerCase() }}</span>
      <span v-if="op.entity_id" class="font-mono text-xs text-text-3">{{ op.entity_id }}</span>
    </li>
    <li v-if="ops.length > 20" class="text-sm text-text-3">and {{ ops.length - 20 }} more</li>
  </ul>
</template>
