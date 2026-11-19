<script setup lang="ts">
import { ApPanel, ApTable, ApTag, formatShort, plural, type ApColumn, type OpState } from "@/ui";
import type { ImportRun, ImportStatus } from "./api.ts";
import { matchTag, sameAsTag } from "./matchedWords.ts";

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

/**
 * #119 U99 (mms-ux's rule): a run with a match and no revision of its own matched in this
 * database ("Matches rev 4", never "Valid"); one that made its own revision and matched is the
 * other-database case (its tag plus "Same as Bus catalog rev 4").
 */
function tags(run: ImportRun) {
  const m = run.matched;
  if (!m) return [status(run.status)];
  if (run.revision_number === null) return [matchTag(m)];
  const same = sameAsTag(m);
  return same ? [status(run.status), same] : [status(run.status)];
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
      <template #cell-status="{ row }"
        ><span class="flex flex-wrap gap-1"
          ><ApTag v-for="t in tags(row)" :key="t.label" v-bind="t" /></span
      ></template>
      <template #cell-diagnostics="{ row }">
        <span :class="row.diagnostic_counts.error > 0 ? 'text-crit-text' : 'text-text-3'">{{
          diagnostics(row)
        }}</span>
      </template>
      <template #cell-started="{ row }">{{ formatShort(new Date(row.started_at)) }}</template>
    </ApTable>
  </ApPanel>
</template>
