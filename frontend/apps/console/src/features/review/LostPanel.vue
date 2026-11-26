<script setup lang="ts">
import {
  ApButton,
  ApEmptyState,
  ApPanel,
  ApTable,
  ApTag,
  formatAbsolute,
  formatCount,
  type ApColumn,
} from "@/ui";
import type { ReviewRow } from "./api.ts";
import { bytes, causeText, duration, outcomeTag, ownerWord, stationText } from "./format.ts";

/**
 * R4 · Missed and partial passes. Volume is provider-reported vs what Cadence received (never a
 * planned figure: none exists). No dispute marks: billing is out of scope (DECISIONS #63, U34).
 */
defineProps<{
  /** Every page loaded so far, in order. */
  rows: readonly ReviewRow[];
  /** How many lost passes match the window, whatever the pages. */
  total: number;
  hasMore: boolean;
  loading: boolean;
  failed: boolean;
}>();
defineEmits<{ more: [] }>();
const columns: readonly ApColumn[] = [
  { key: "aos", label: "AOS", mono: true },
  { key: "spacecraft", label: "Spacecraft", mono: true },
  { key: "antenna", label: "Station · antenna" },
  { key: "outcome", label: "Outcome" },
  { key: "flown", label: "Flown / planned", mono: true, align: "end" },
  { key: "volume", label: "Received / reported", mono: true, align: "end" },
  { key: "cause", label: "Cause" },
  { key: "owner", label: "Owner" },
];
</script>

<template>
  <ApPanel index="R4" title="Missed and partial passes" flush>
    <ApEmptyState v-if="rows.length === 0" state="off" headline="No missed or partial passes" />
    <ApTable
      v-else
      :columns="columns"
      :rows="rows"
      :row-key="(r) => r.id"
      caption="Missed and partial passes"
    >
      <template #cell-aos="{ row }">{{ formatAbsolute(new Date(row.planned_aos)) }}</template>
      <template #cell-spacecraft="{ row }">{{
        row.spacecraft.name ?? "Unknown spacecraft"
      }}</template>
      <template #cell-antenna="{ row }"
        >{{ stationText(row.station)
        }}<span v-if="row.antenna_ref" class="block font-mono text-xs text-text-3">{{
          row.antenna_ref
        }}</span></template
      >
      <template #cell-outcome="{ row }"><ApTag v-bind="outcomeTag(row.outcome)" /></template>
      <template #cell-flown="{ row }"
        >{{ row.flown_seconds === null ? "—" : duration(row.flown_seconds) }}
        <span class="text-text-3">/ {{ duration(row.planned_seconds) }}</span></template
      >
      <template #cell-volume="{ row }"
        >{{ bytes(row.received_bytes) }}
        <span class="text-text-3">/ {{ bytes(row.provider_bytes) }}</span></template
      >
      <template #cell-cause="{ row }">{{ causeText(row.cause) }}</template>
      <template #cell-owner="{ row }">{{ row.owner ? ownerWord[row.owner] : "—" }}</template>
      <template #footer>
        <div
          class="flex flex-wrap items-center gap-3 border-t border-hairline px-4 py-2.5 font-mono text-xs text-text-3 uppercase"
        >
          <span>Showing {{ formatCount(rows.length) }} of {{ formatCount(total) }}</span>
          <ApButton
            v-if="hasMore"
            size="compact"
            :disabled="loading"
            disabled-reason="Loading…"
            @click="$emit('more')"
            >Load more</ApButton
          >
          <!-- ux U72, a11y B6: a failed Load more is said next to it as an alert, always mounted
            so it's announced; usePagedQuery clears it as Load more starts again. -->
          <span role="alert" class="text-caution-text normal-case">{{
            failed ? "More passes couldn't load. Try Load more again." : ""
          }}</span>
        </div>
      </template>
    </ApTable>
  </ApPanel>
</template>
