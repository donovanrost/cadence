<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton, ApSheet, ApTable, type ApColumn } from "@/ui";
import type { WorkspacePlacement } from "../model/snapshot.ts";
import { fieldStats, inspectTable, toCsv } from "../model/inspect-data.ts";

/** ⋯ › Inspect: the widget's numbers as statistics and rows (newest first), plus a CSV of all rows. */
const placement = ref<WorkspacePlacement | null>(null);
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const title = computed(() =>
  placement.value?.status === "ready" ? `Inspect · ${placement.value.widget.title}` : "Inspect",
);
const stats = computed(() => (placement.value ? fieldStats(placement.value) : []));
const data = computed(() => (placement.value ? inspectTable(placement.value) : null));
const fmt = (v: number | null) => (v === null ? "—" : Number(v.toPrecision(6)).toString());
const statColumns: readonly ApColumn[] = [
  { key: "field", label: "Field" },
  ...(["count", "min", "max", "mean", "last"] as const).map((key) => ({
    key,
    label: key,
    align: "end" as const,
    mono: true,
  })),
];
const statRows = computed(() =>
  stats.value.map((s) => ({
    key: s.key,
    field: s.unit ? `${s.name} (${s.unit})` : s.name,
    count: s.count,
    min: fmt(s.min),
    max: fmt(s.max),
    mean: fmt(s.mean),
    last: fmt(s.last),
  })),
);
const dataColumns = computed<readonly ApColumn[]>(() =>
  (data.value?.columns ?? []).map((c, i) => ({
    key: String(i),
    label: c.unit ? `${c.name} (${c.unit})` : c.name,
    mono: true,
  })),
);
const dataRows = computed(() =>
  (data.value?.rows ?? []).map((row, i) => ({
    key: String(i),
    ...Object.fromEntries(row.map((v, c) => [String(c), v])),
  })),
);

function download() {
  const p = placement.value;
  if (!p) return;
  const url = URL.createObjectURL(new Blob([toCsv(p)], { type: "text/csv" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = `${p.authored_id}.csv`;
  a.click();
  URL.revokeObjectURL(url);
}
function open(p: WorkspacePlacement) {
  placement.value = p;
  sheet.value?.open();
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" :title="title" width="wide">
    <div class="flex flex-col gap-4">
      <ApTable
        v-if="statRows.length"
        caption="Series statistics"
        :columns="statColumns"
        :rows="statRows"
        :row-key="(r) => r.key"
      />
      <ApTable
        caption="Data, newest first"
        :columns="dataColumns"
        :rows="dataRows"
        :row-key="(r) => r.key"
      />
      <p v-if="data?.truncated" class="m-0 text-sm text-text-3">
        Showing the newest 500 rows. The CSV has every row.
      </p>
    </div>
    <template #footer>
      <ApButton variant="secondary" class="mr-auto" @click="download">Download CSV</ApButton>
      <ApButton variant="primary" @click="sheet?.close()">Close</ApButton>
    </template>
  </ApSheet>
</template>
