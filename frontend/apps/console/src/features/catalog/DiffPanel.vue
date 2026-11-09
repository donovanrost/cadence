<script setup lang="ts">
import { computed, ref } from "vue";
import { ApPanel, ApSegmented, ApTable, type ApColumn } from "@/ui";
import type { ImportRunDetail } from "./importRun.ts";

/** C1 Diff: changes sorted by risk (breaking first), filterable (Catalog.md § C1). */
type Diff = NonNullable<ImportRunDetail["diff"]>;
const props = defineProps<{ diff: Diff }>();
type Filter = "all" | "breaking" | "added" | "changed" | "removed";
const filter = ref<Filter>("all");
const sorted = computed(() =>
  [...props.diff.changes].sort((a, b) => Number(b.breaking) - Number(a.breaking)),
);
const count = (f: Filter) =>
  f === "all"
    ? sorted.value.length
    : f === "breaking"
      ? sorted.value.filter((c) => c.breaking).length
      : sorted.value.filter((c) => c.op === f).length;
const options = computed(() =>
  (["all", "breaking", "added", "changed", "removed"] as const).map((f) => ({
    value: f,
    label: f[0]?.toUpperCase() + f.slice(1),
    count: count(f),
  })),
);
const rows = computed(() =>
  sorted.value.filter(
    (c) =>
      filter.value === "all" || (filter.value === "breaking" ? c.breaking : c.op === filter.value),
  ),
);
const columns: readonly ApColumn[] = [
  { key: "op", label: "Op", mono: true },
  { key: "kind", label: "Kind", mono: true },
  { key: "name", label: "Name", mono: true },
  { key: "change", label: "Change" },
];
const glyph = (op: string) => (op === "added" ? "+" : op === "removed" ? "−" : "~");
</script>

<template>
  <ApPanel index="C1" title="Diff" meta="Sorted by risk" flush>
    <div class="px-4 py-2.5">
      <ApSegmented v-model="filter" :options="options" label="Filter changes" variant="tabs" />
    </div>
    <ApTable
      :columns="columns"
      :rows="rows"
      :row-key="(c) => `${c.kind}-${c.name}`"
      caption="Catalog changes"
      :row-state="(c) => (c.breaking ? 'caution' : null)"
    >
      <template #cell-op="{ row }"
        ><span class="text-[15px] font-semibold">{{ glyph(row.op) }}</span></template
      >
      <template #cell-kind="{ row }">{{
        row.kind === "command" ? "CMD" : row.kind === "telemetry" ? "TLM" : "—"
      }}</template>
      <template #cell-change="{ row }"
        ><span class="text-text-2">{{ row.change }}</span></template
      >
    </ApTable>
  </ApPanel>
</template>
