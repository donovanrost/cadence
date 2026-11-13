<script setup lang="ts">
import { computed } from "vue";
import { ApPanel, ApTable, type ApColumn } from "@/ui";
import type { StationLine } from "./api.ts";
import { byRealization, minutes, percent, stationRatio, stationText } from "./format.ts";

/** R1 · By station, worst realization first. No billing, so no billed minutes. */
const props = defineProps<{ lines: readonly StationLine[] }>();
/** One provider: named once in the meta, not repeated per row. */
const providers = computed(() => [...new Set(props.lines.map((l) => l.provider?.name ?? "—"))]);
const columns = computed((): readonly ApColumn[] => [
  { key: "station", label: "Station" },
  ...(providers.value.length > 1 ? [{ key: "provider", label: "Provider" }] : []),
  { key: "planned", label: "Planned", mono: true, align: "end" },
  { key: "realized", label: "Realized" },
  { key: "partial", label: "Partial", mono: true, align: "end" },
  { key: "missed", label: "Missed", mono: true, align: "end" },
  { key: "flown", label: "Minutes flown", mono: true, align: "end" },
]);
const meta = computed(() =>
  providers.value.length === 1
    ? `${providers.value[0]} · worst first`
    : "Sorted by realization, worst first",
);
</script>

<template>
  <ApPanel index="R1" title="By station" :meta="meta" flush>
    <ApTable
      :columns="columns"
      :rows="byRealization(lines)"
      :row-key="(l) => l.station.id ?? l.station.ref ?? stationText(l.station)"
      caption="Realization by station"
    >
      <template #cell-station="{ row }">
        <span class="whitespace-nowrap">{{ row.station.name ?? row.station.ref }}</span>
        <span v-if="row.station.code" class="ml-1.5 font-mono text-xs text-text-3">{{
          row.station.code
        }}</span>
      </template>
      <template #cell-provider="{ row }"
        ><span class="text-text-3">{{ row.provider?.name ?? "—" }}</span></template
      >
      <template #cell-realized="{ row }">
        <span class="inline-flex items-center gap-2 font-mono">
          <span class="h-1 w-16 bg-hairline" aria-hidden="true"
            ><span
              class="block h-full bg-nominal"
              :style="{ width: `${Math.round((stationRatio(row) ?? 0) * 100)}%` }"
          /></span>
          {{ percent(stationRatio(row)) }}
        </span>
      </template>
      <template #cell-partial="{ row }"
        ><span :class="row.partial > 0 ? 'text-caution-text' : ''">{{
          row.partial
        }}</span></template
      >
      <template #cell-missed="{ row }"
        ><span :class="row.missed + row.failed > 0 ? 'text-crit-text' : ''">{{
          row.missed + row.failed
        }}</span></template
      >
      <template #cell-flown="{ row }"
        ><span class="whitespace-nowrap"
          >{{ Math.round(row.flown_seconds / 60) }}
          <span class="text-text-3">/ {{ minutes(row.planned_seconds) }}</span></span
        ></template
      >
    </ApTable>
  </ApPanel>
</template>
