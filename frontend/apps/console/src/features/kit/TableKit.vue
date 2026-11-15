<script setup lang="ts">
import { ApPanel, ApTable, type ApColumn } from "@/ui";

/**
 * Development-only review of ApTable's opt-in windowing (lead's kit, 11-15): 1,000 fixture rows
 * in a scrolling panel. Only the rows in view (plus overscan) are in the DOM; Tab walks every row.
 * Find-in-page can't see the rows that aren't rendered (the documented limit).
 */
type Row = Readonly<{ id: string; name: string; scid: number; state: string }>;
const states = ["Nominal", "Caution", "Critical", "Stale"];
const rows: Row[] = Array.from({ length: 1000 }, (_, i) => ({
  id: `fixture-${i}`,
  name: `FIXTURE-${String(i + 1).padStart(4, "0")}`,
  scid: i + 1,
  state: states[i % states.length] ?? "Nominal",
}));
const columns: readonly ApColumn[] = [
  { key: "name", label: "Name" },
  { key: "scid", label: "SCID", mono: true, align: "end" },
  { key: "state", label: "State" },
];
</script>

<template>
  <ApPanel index="K5" title="ApTable · virtual" meta="1,000 FIXTURE ROWS · ROW HEIGHT 41 PX">
    <div class="h-[420px] overflow-auto">
      <ApTable
        :columns="columns"
        :rows="rows"
        :row-key="(r) => r.id"
        caption="Fixture rows"
        :virtual="{ rowHeight: 41 }"
      >
        <template #cell-name="{ row }">
          <a :href="`#${row.id}`" class="text-readout no-underline hover:underline">{{
            row.name
          }}</a>
        </template>
      </ApTable>
    </div>
  </ApPanel>
</template>
