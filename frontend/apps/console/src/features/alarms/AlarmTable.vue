<script setup lang="ts">
import { RouterLink } from "vue-router";
import {
  formatAbsolute,
  formatCountdown,
  useNow,
  ApStatusMark,
  ApTable,
  type ApColumn,
} from "@/ui";
import { conditionWords, crossedCondition } from "./api.ts";
import { formatLimitLike, formatValue, withUnit } from "./format.ts";
import type { AlarmListRow } from "./list.ts";

/** L1 · Alarm table. The Spacecraft cell links to Investigate for that alarm (rule: name-cell link). */
defineProps<{ rows: readonly AlarmListRow[] }>();
const now = useNow();

const columns: readonly ApColumn[] = [
  { key: "severity", label: "Severity" },
  { key: "spacecraft", label: "Spacecraft" },
  { key: "point", label: "Point" },
  { key: "value", label: "Now / limit", mono: true, align: "end" },
  { key: "crossed", label: "First crossed", mono: true },
];

const tint = (row: AlarmListRow) =>
  row.alarm.severity === "critical"
    ? "text-crit-text"
    : row.alarm.severity === "caution"
      ? "text-caution-text"
      : "";
const state = (row: AlarmListRow) =>
  row.alarm.severity === "critical" ? "crit" : row.alarm.severity === "caution" ? "caution" : null;
</script>

<template>
  <ApTable
    :columns="columns"
    :rows="rows"
    :row-key="(row) => row.alarm.id"
    caption="Active alarms"
    :row-state="state"
  >
    <template #cell-severity="{ row }">
      <span
        class="inline-flex items-center gap-2 font-display text-md font-semibold tracking-tag uppercase"
        :class="tint(row)"
      >
        <ApStatusMark :state="state(row) ?? 'nominal'" />{{ row.alarm.severity }}
      </span>
    </template>
    <template #cell-spacecraft="{ row }">
      <RouterLink
        v-if="row.sc"
        :to="{
          name: 'ops.spacecraft',
          params: { scId: String(row.sc.scid), tab: 'investigate' },
          query: { alarm: row.alarm.id },
        }"
        class="max-md:hit-44 whitespace-nowrap text-readout no-underline hover:text-bright hover:underline"
        >{{ row.sc.name }}</RouterLink
      >
      <span v-else class="text-text-3">Mission</span>
    </template>
    <template #cell-point="{ row }">
      <span class="text-readout">{{ row.alarm.point.name }}</span>
      <span class="text-text-3">
        · {{ conditionWords(crossedCondition(row.alarm)) ?? "out of limits" }}</span
      >
    </template>
    <template #cell-value="{ row }">
      <span :class="tint(row)">{{
        withUnit(formatValue(row.alarm.value), row.alarm.point.unit) ?? "—"
      }}</span>
      <span class="text-text-4">
        /
        {{
          withUnit(formatLimitLike(row.limit, row.alarm.value), row.alarm.point.unit) ?? "—"
        }}</span
      >
    </template>
    <template #cell-crossed="{ row }">
      <time
        v-if="row.alarm.first_crossed_at"
        :datetime="row.alarm.first_crossed_at"
        :title="formatAbsolute(new Date(row.alarm.first_crossed_at))"
        >{{ formatCountdown(new Date(row.alarm.first_crossed_at), now) }}</time
      >
      <span v-else class="text-text-4">—</span>
    </template>
  </ApTable>
</template>
