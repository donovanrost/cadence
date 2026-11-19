<script setup lang="ts">
import { ApPanel, ApTable, ApTag, plural, type ApColumn, type OpState } from "@/ui";
import { startedLine, type ImportRun, type ImportStatus } from "./api.ts";

/** Recent import runs; each links to its validation + diff page. */
defineProps<{ runs: readonly ImportRun[] }>();

const columns: readonly ApColumn[] = [
  { key: "file", label: "File" },
  { key: "status", label: "Status" },
  { key: "diagnostics", label: "Diagnostics" },
  { key: "started", label: "Started", mono: true },
];

function status(s: ImportStatus): { state: OpState; label: string } {
  switch (s) {
    case "running":
      return { state: "live", label: "Parsing" };
    case "succeeded":
      return { state: "nominal", label: "Valid" };
    case "failed":
      return { state: "crit", label: "Failed" };
  }
}

function diagnostics(run: ImportRun): string {
  const c = run.diagnostic_counts;
  const parts = [
    c.error > 0 ? plural(c.error, "error") : null,
    c.warning > 0 ? plural(c.warning, "warning") : null,
  ].filter((p): p is string => p !== null);
  return parts.length > 0 ? parts.join(" · ") : "none";
}
</script>

<template>
  <ApPanel index="A2" title="Import runs" flush>
    <ApTable :columns="columns" :rows="runs" :row-key="(r) => r.id" caption="Catalog import runs">
      <template #cell-file="{ row }">
        <RouterLink
          :to="{ name: 'setup.catalog.import', params: { importId: row.id } }"
          class="font-mono text-readout no-underline hover:text-bright hover:underline max-md:hit-44"
          >{{ row.file_name }}</RouterLink
        >
        <span v-if="row.revision_number !== null" class="block text-xs text-text-4"
          >rev {{ row.revision_number }}</span
        >
      </template>
      <template #cell-status="{ row }"><ApTag v-bind="status(row.status)" /></template>
      <template #cell-diagnostics="{ row }">
        <span :class="row.diagnostic_counts.error > 0 ? 'text-crit-text' : 'text-text-3'">{{
          diagnostics(row)
        }}</span>
      </template>
      <template #cell-started="{ row }">{{ startedLine(row) }}</template>
    </ApTable>
  </ApPanel>
</template>
