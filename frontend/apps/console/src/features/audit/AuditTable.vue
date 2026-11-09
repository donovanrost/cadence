<script setup lang="ts">
import { ApTable, ApTag, formatAbsolute, type ApColumn } from "@/ui";
import { computed } from "vue";
import { groupRepeats, targetText, type AuditEvent } from "./api.ts";

/** Audit rows, newest first: time · actor · action in words · mission · why. */
const props = defineProps<{ events: readonly AuditEvent[] }>();
const rows = computed(() => groupRepeats(props.events));
const columns: readonly ApColumn[] = [
  { key: "at", label: "Time", mono: true },
  { key: "actor", label: "Actor" },
  { key: "action", label: "Action" },
  { key: "mission", label: "Mission" },
  { key: "why", label: "Why" },
];
</script>

<template>
  <ApTable :columns="columns" :rows="rows" :row-key="(e) => e.id" caption="Audit log">
    <template #cell-at="{ row }">{{ formatAbsolute(new Date(row.at)) }}</template>
    <template #cell-actor="{ row }">
      <template v-if="row.actor">
        <span :class="row.actor.kind === 'service' ? 'font-mono' : ''">{{ row.actor.name }}</span>
        <ApTag v-if="row.actor.kind === 'service'" class="ml-2" label="Service" />
      </template>
      <span v-else class="text-text-3">Not recorded</span>
    </template>
    <template #cell-action="{ row }"
      >{{ row.action
      }}<span v-if="targetText(row)" class="text-text-3"> · {{ targetText(row) }}</span
      ><span v-if="row.repeat > 1" class="font-mono text-text-3"> ×{{ row.repeat }}</span></template
    >
    <template #cell-mission="{ row }">{{ row.mission?.name ?? "—" }}</template>
    <template #cell-why="{ row }"
      ><span class="text-text-3">{{ row.reason ?? "" }}</span></template
    >
    <template #footer><slot name="footer" /></template>
  </ApTable>
</template>
