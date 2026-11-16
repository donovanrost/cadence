<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { ApStatusMark, ApTable, ApTag, type ApColumn } from "@/ui";
import { isHandStarted } from "../handStarted.ts";
import type { HistoryRow } from "./history.ts";
import type { LedgerItem } from "./useHistory.ts";
import IdCell from "./IdCell.vue";
import { dayTime, shortDayRow, stateView, stationName, windowText } from "./words.ts";

/**
 * U78 ledger. Wide: Window · Spacecraft · Station · State · Provider revision · Reservation ·
 * Scheduled contact; 768–1099 drops the two ids; a phone keeps a table: Start · Pass · State.
 * The Window (phone: Start) cell is the row link to `?contact=`; never whole-row click. A
 * hand-started contact carries a HAND-STARTED tag and no reservation, revision or schedule (—).
 */
const props = defineProps<{
  items: readonly LedgerItem[];
  width: "phone" | "mid" | "wide";
  selectedId: string | null;
  caption: string;
  /** The spacecraft's name for a row (fleet row, else the row's own). */
  spacecraftName: (r: HistoryRow) => string;
}>();
const route = useRoute();
const columns = computed<readonly ApColumn[]>(() => {
  if (props.width === "phone") {
    return [
      { key: "start", label: "Start", mono: true },
      { key: "pass", label: "Pass" },
      { key: "state", label: "State" },
    ];
  }
  const ids: ApColumn[] =
    props.width === "wide"
      ? [
          { key: "reservation", label: "Reservation", mono: true },
          { key: "scheduled", label: "Scheduled contact", mono: true },
        ]
      : [];
  return [
    { key: "window", label: "Window", mono: true },
    { key: "spacecraft", label: "Spacecraft" },
    { key: "station", label: "Station" },
    { key: "state", label: "State" },
    { key: "revision", label: "Provider revision", mono: true, align: "end" },
    ...ids,
  ];
});
const to = (r: HistoryRow) => ({ query: { ...route.query, contact: r.id } });
const linkClass =
  "font-semibold whitespace-nowrap text-readout no-underline hover:text-bright hover:underline max-md:hit-44";
const booked = (r: HistoryRow) => (isHandStarted(r) ? null : r);
</script>

<template>
  <ApTable :columns="columns" :rows="items" :row-key="(i) => i.key" :caption="caption">
    <template #cell-window="{ row }">
      <span v-if="row.kind === 'gap'" class="text-text-3">{{ shortDayRow(row.day) }}</span>
      <span v-else class="inline-flex flex-wrap items-center gap-2">
        <RouterLink
          :to="to(row.pass)"
          :class="linkClass"
          :aria-current="row.pass.id === selectedId ? 'true' : undefined"
          >{{ windowText(row.pass) }}</RouterLink
        >
        <ApTag v-if="isHandStarted(row.pass)" label="HAND-STARTED" />
      </span>
    </template>
    <template #cell-start="{ row }">
      <span v-if="row.kind === 'gap'" class="text-text-3">{{ shortDayRow(row.day) }}</span>
      <span v-else class="inline-flex flex-wrap items-center gap-2">
        <RouterLink
          :to="to(row.pass)"
          :class="linkClass"
          :aria-current="row.pass.id === selectedId ? 'true' : undefined"
          >{{ dayTime(Date.parse(row.pass.starts_at)) }}</RouterLink
        >
        <ApTag v-if="isHandStarted(row.pass)" label="HAND-STARTED" />
      </span>
    </template>
    <template #cell-pass="{ row }">
      <template v-if="row.kind === 'pass'">
        <span class="block">{{ spacecraftName(row.pass) }}</span>
        <span class="block text-text-3"
          >{{ stationName(row.pass.station) }}
          <span v-if="row.pass.station.code" class="font-mono">{{
            row.pass.station.code
          }}</span></span
        >
      </template>
    </template>
    <template #cell-spacecraft="{ row }">
      <template v-if="row.kind === 'pass'">{{ spacecraftName(row.pass) }}</template>
    </template>
    <template #cell-station="{ row }">
      <template v-if="row.kind === 'pass'"
        >{{ stationName(row.pass.station) }}
        <span v-if="row.pass.station.code" class="font-mono text-text-3">{{
          row.pass.station.code
        }}</span></template
      >
    </template>
    <template #cell-state="{ row }">
      <span v-if="row.kind === 'pass'" class="inline-flex items-center gap-2 whitespace-nowrap"
        ><ApStatusMark :state="stateView(row.pass).state" />{{ stateView(row.pass).word }}</span
      >
    </template>
    <template #cell-revision="{ row }">
      <template v-if="row.kind === 'pass'">{{
        booked(row.pass)?.provider_revision ?? "—"
      }}</template>
    </template>
    <template #cell-reservation="{ row }">
      <IdCell v-if="row.kind === 'pass'" :id="booked(row.pass)?.id" label="reservation id" />
    </template>
    <template #cell-scheduled="{ row }">
      <IdCell
        v-if="row.kind === 'pass'"
        :id="booked(row.pass)?.scheduled_contact_id"
        label="scheduled contact id"
      />
    </template>
  </ApTable>
</template>
