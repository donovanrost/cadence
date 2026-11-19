<script setup lang="ts">
import { computed, ref } from "vue";
import { ApGantt, ApPanel, useNow, type GanttBand, type GanttBar, type GanttRow } from "@/ui";

/** Development-only review of ApGantt with fixture rows and bars (no real passes). */
const now = useNow();
const H = 3_600_000;
const start = computed(() => Math.floor(now.value.getTime() / (24 * H)) * 24 * H);
const window = computed(() => ({ from: start.value, to: start.value + 24 * H }));
const rows: GanttRow[] = [
  { id: "svb1", label: "SVB-1", tag: "UP" },
  { id: "svb2", label: "SVB-2" },
  { id: "fbk1", label: "FBK-1", tag: "UP", degraded: true },
  { id: "awa1", label: "AWA-1" },
];
const kinds = [
  "own",
  "window",
  "own",
  "focused",
  "clash",
  "new",
  "problem",
  "live",
  "scheduled",
] as const;
const bars = computed<GanttBar[]>(() =>
  rows.flatMap((row, r) =>
    Array.from({ length: 9 }, (_, i) => {
      const kind = kinds[(i + r) % kinds.length] ?? "own";
      const from = start.value + (i * 2.6 + r * 0.7) * H;
      return {
        id: `${row.id}-${i}`,
        rowId: row.id,
        from,
        to: from + 0.17 * H,
        kind,
        label: String(100 + i * 7 + r),
        description: `Fixture ${kind} pass ${100 + i * 7 + r} on ${row.label}`,
      };
    }),
  ),
);
const bands = computed<GanttBand[]>(() => [
  {
    rowId: "fbk1",
    from: start.value + 6 * H,
    to: start.value + 9 * H,
    kind: "maintenance",
    label: "Maintenance",
  },
  {
    rowId: "awa1",
    from: start.value + 14 * H,
    to: start.value + 17 * H,
    kind: "outage",
    label: "Outage",
  },
]);
const selected = ref<string | null>(null);
</script>

<template>
  <ApPanel index="K4" title="ApGantt" meta="FIXTURES · 00–24Z">
    <ApGantt
      label="Fixture draft by station"
      :rows="rows"
      :bars="bars"
      :bands="bands"
      :window="window"
      :now="now.getTime()"
      :selected="selected"
      @select="selected = $event"
    />
    <p class="m-0 mt-2 font-mono text-xs text-text-4">Selected: {{ selected ?? "none" }}</p>
  </ApPanel>
</template>
