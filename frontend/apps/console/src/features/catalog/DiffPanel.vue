<script setup lang="ts">
import { computed, ref } from "vue";
import { ApPanel, ApSegmented, ApTable, ApTag, type ApColumn } from "@/ui";
import type { ImportRunDetail } from "./importRun.ts";

/** C1 Diff: changes sorted by risk (breaking first), filterable (Catalog.md § C1). */
type Diff = NonNullable<ImportRunDetail["diff"]>;
const props = defineProps<{ diff: Diff; baseNumber: number | null }>();
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
/** a11y B2: the glyph is aria-hidden; its word is read instead, and Breaking is a word, not just the wash. */
type Op = Diff["changes"][number]["op"];
const OP_WORD = {
  added: "Added",
  changed: "Changed",
  removed: "Removed",
} as const satisfies Record<Op, string>;
const opWord = (op: Op) => OP_WORD[op];
</script>

<template>
  <ApPanel
    index="C1"
    title="Diff"
    :meta="baseNumber === null ? 'Sorted by risk' : `Against r${baseNumber} · sorted by risk`"
    flush
  >
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
        ><span class="text-[15px] font-semibold" aria-hidden="true">{{ glyph(row.op) }}</span
        ><span class="sr-only">{{ opWord(row.op) }}</span></template
      >
      <template #cell-kind="{ row }">{{
        row.kind === "command" ? "CMD" : row.kind === "telemetry" ? "TLM" : "—"
      }}</template>
      <template #cell-change="{ row }"
        ><span class="flex flex-wrap items-center gap-2"
          ><ApTag v-if="row.breaking" state="caution" label="Breaking" /><span
            class="text-text-2"
            >{{ row.change ?? "—" }}</span
          ></span
        ></template
      >
      <template v-if="diff.truncated" #footer>
        <p class="m-0 border-t border-hairline px-4 py-2.5 font-mono text-xs text-text-3 uppercase">
          Showing the first {{ diff.changes.length }} changes, breaking first. The counts above
          cover all of them.
        </p>
      </template>
    </ApTable>
  </ApPanel>
</template>
