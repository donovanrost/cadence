<script setup lang="ts">
import { ApEmptyState, ApPanel, ApTable, ApTag, formatAbsolute, type ApColumn } from "@/ui";
import type { ReviewRows } from "./api.ts";
import { bytes, causeText, duration, outcomeTag, ownerWord, stationText } from "./format.ts";

/**
 * R4 · Missed and partial passes. Volume is provider-reported vs what Cadence received (never a
 * planned figure: none exists). Disputes have no flow yet (no billing), so they're marked, not linked.
 */
defineProps<{ page: ReviewRows }>();
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
    <ApEmptyState
      v-if="page.rows.length === 0"
      state="off"
      headline="No missed or partial passes"
    />
    <ApTable
      v-else
      :columns="columns"
      :rows="page.rows"
      :row-key="(r) => r.id"
      caption="Missed and partial passes"
    >
      <template #cell-aos="{ row }">{{ formatAbsolute(new Date(row.planned_aos)) }}</template>
      <template #cell-spacecraft="{ row }">{{ row.spacecraft.name ?? row.spacecraft.id }}</template>
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
      <template #cell-owner="{ row }"
        >{{ row.owner ? ownerWord[row.owner] : "—"
        }}<span v-if="row.disputable" class="block font-mono text-xs text-caution-text uppercase"
          >Disputable</span
        ></template
      >
      <template #footer>
        <p class="m-0 border-t border-hairline px-4 py-2.5 font-mono text-xs text-text-3 uppercase">
          Showing {{ page.rows.length }} of {{ page.total }} · {{ page.disputable }} disputable
        </p>
      </template>
    </ApTable>
  </ApPanel>
</template>
