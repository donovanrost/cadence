<script setup lang="ts">
import { RouterLink } from "vue-router";
import { formatCount, formatDuration, ApStatusMark, ApTable, type ApColumn } from "@/ui";
import type { FleetSpacecraft } from "./api.ts";
import { useCoarseNow } from "./coarseClock.ts";
import { nextContact } from "./filters.ts";
import { fleetOpState, fleetStateWord } from "./matrix.ts";

/** Fleet table: Name links to the spacecraft (Investigate); state is mark + word (+ worst point). */
defineProps<{
  rows: readonly FleetSpacecraft[];
  total: number;
  /** The table is its own scroll box (FleetScreen decides: OpsLists.md › Fleet, option A). */
  boxed?: boolean;
}>();
/** Last TLM and Next contact move every 10 s, so 500 rows don't re-render each second. */
const now = useCoarseNow();

/**
 * Lead (scale, 11-15): at 1,000 craft a full table is 14,000 nodes and a reorder takes ~117 ms, so
 * only the rows in view render (ApTable's windowing). Rows are one line; 41 px pins their height.
 */
const ROW_HEIGHT = 41;
const columns: readonly ApColumn[] = [
  { key: "name", label: "Name" },
  { key: "scid", label: "SCID", mono: true, align: "end" },
  { key: "state", label: "State" },
  { key: "orbit", label: "Plane · slot", mono: true },
  { key: "profile", label: "Profile" },
  { key: "tlm", label: "Last TLM", mono: true, align: "end" },
  { key: "contact", label: "Next contact", mono: true, align: "end" },
];
const orbit = (sc: FleetSpacecraft) =>
  sc.plane === null
    ? "—"
    : `P${String(sc.plane).padStart(2, "0")}${sc.slot === null ? "" : ` · ${String(sc.slot).padStart(2, "0")}`}`;
const age = (sc: FleetSpacecraft) =>
  sc.last_received_at
    ? formatDuration((now.value - Date.parse(sc.last_received_at)) / 1000)
    : "never";
const tint = (sc: FleetSpacecraft) =>
  sc.state === "critical"
    ? "text-crit-text"
    : sc.state === "caution"
      ? "text-caution-text"
      : sc.state === "stale"
        ? "text-stale-text"
        : "text-text-2";
const rowState = (sc: FleetSpacecraft) =>
  sc.state === "critical"
    ? "crit"
    : sc.state === "caution"
      ? "caution"
      : sc.state === "stale"
        ? "stale"
        : null;
</script>

<template>
  <ApTable
    :columns="columns"
    :rows="rows"
    :row-key="(sc) => sc.id"
    caption="Fleet table"
    :row-state="rowState"
    :virtual="{ rowHeight: ROW_HEIGHT }"
    :scroll-box="boxed"
  >
    <template #cell-name="{ row }">
      <RouterLink
        :to="{ name: 'ops.spacecraft', params: { scId: row.scid } }"
        class="max-md:hit-44 whitespace-nowrap text-readout no-underline hover:text-bright hover:underline"
        >{{ row.name }}</RouterLink
      >
    </template>
    <template #cell-state="{ row }">
      <span class="inline-flex items-center gap-2" :class="tint(row)">
        <ApStatusMark :state="fleetOpState(row.state)" />{{ fleetStateWord(row.state)
        }}<template v-if="row.worst_point"> · {{ row.worst_point.point_name }}</template>
      </span>
    </template>
    <template #cell-orbit="{ row }">{{ orbit(row) }}</template>
    <template #cell-profile="{ row }"
      ><span class="text-text-2">{{ row.profile?.name ?? "—" }}</span></template
    >
    <template #cell-tlm="{ row }"
      ><span :class="row.stale ? 'text-stale-text' : 'text-text-3'">{{ age(row) }}</span></template
    >
    <template #cell-contact="{ row }"
      ><span :class="row.in_contact ? 'text-readout' : 'text-text-3'">{{
        nextContact(row, new Date(now)) ?? "—"
      }}</span></template
    >
    <template #footer>
      <p class="m-0 px-4 py-2.5 font-mono text-xs text-text-4 uppercase">
        {{ formatCount(rows.length) }} of {{ formatCount(total) }}
      </p>
    </template>
  </ApTable>
</template>
