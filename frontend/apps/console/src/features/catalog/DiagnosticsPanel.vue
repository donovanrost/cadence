<script setup lang="ts">
import { computed } from "vue";
import {
  ApPanel,
  ApStatusMark,
  ApTable,
  formatCount,
  plural,
  type ApColumn,
  type OpState,
} from "@/ui";
import { groupDiagnostics, type Diagnostic } from "./importRun.ts";

/** Importer diagnostics, identical ones grouped with a count (Catalog.md § C). */
const props = defineProps<{ diagnostics: readonly Diagnostic[]; index: string }>();
const groups = computed(() => groupDiagnostics(props.diagnostics));
const columns: readonly ApColumn[] = [
  { key: "severity", label: "Severity" },
  { key: "count", label: "Count", mono: true, align: "end" },
  { key: "code", label: "Code", mono: true },
  { key: "message", label: "Message" },
  { key: "paths", label: "Where", mono: true },
];
const mark = (s: Diagnostic["severity"]): OpState =>
  s === "error" ? "crit" : s === "warning" ? "caution" : "neutral";
const word = (s: Diagnostic["severity"]) =>
  s === "error" ? "Error" : s === "warning" ? "Warning" : "Info";
</script>

<template>
  <ApPanel
    :index="index"
    title="Diagnostics"
    :meta="`${formatCount(diagnostics.length)} items → ${plural(groups.length, 'line')}`"
    flush
  >
    <ApTable :columns="columns" :rows="groups" :row-key="(g) => g.key" caption="Import diagnostics">
      <template #cell-severity="{ row }">
        <span class="inline-flex items-center gap-2"
          ><ApStatusMark :state="mark(row.severity)" />{{ word(row.severity) }}</span
        >
      </template>
      <template #cell-count="{ row }">× {{ formatCount(row.count) }}</template>
      <template #cell-paths="{ row }">
        <span class="text-text-3">{{ row.paths.length > 0 ? row.paths.join(", ") : "—" }}</span>
      </template>
    </ApTable>
  </ApPanel>
</template>
