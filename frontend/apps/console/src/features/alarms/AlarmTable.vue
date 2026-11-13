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
import { nextContact } from "@/features/fleet/index.ts";
import { conditionWords } from "./api.ts";
import { formatLimitLike, formatValue, withUnit } from "./format.ts";
import type { AlarmListRow } from "./list.ts";

/** L1 · Alarm episodes. The Spacecraft cell links to Investigate on that point (name-cell link). */
defineProps<{ rows: readonly AlarmListRow[] }>();
const now = useNow();
const columns: readonly ApColumn[] = [
  { key: "severity", label: "Severity" },
  { key: "spacecraft", label: "Spacecraft" },
  { key: "point", label: "Point" },
  { key: "value", label: "Last / limit", mono: true, align: "end" },
  { key: "since", label: "Opened", mono: true },
  { key: "owner", label: "Owner · source" },
  { key: "contact", label: "Next contact", mono: true, align: "end" },
];
const tint = (row: AlarmListRow) =>
  row.episode.severity === "critical" ? "text-crit-text" : "text-caution-text";
const state = (row: AlarmListRow) =>
  row.episode.status === "cleared"
    ? null
    : row.episode.severity === "critical"
      ? "crit"
      : "caution";
const to = (row: AlarmListRow) => ({
  name: "ops.spacecraft",
  params: { scId: String(row.sc?.scid ?? ""), tab: "investigate" },
  query: { point: row.episode.point.id },
});
</script>

<template>
  <ApTable
    :columns="columns"
    :rows="rows"
    :row-key="(row) => row.key"
    caption="Alarms"
    :row-state="state"
  >
    <template #cell-severity="{ row }">
      <span
        class="inline-flex items-center gap-2 font-display text-md font-semibold tracking-tag uppercase"
        :class="tint(row)"
      >
        <ApStatusMark :state="row.episode.severity === 'critical' ? 'crit' : 'caution'" />{{
          row.episode.severity
        }}
      </span>
    </template>
    <template #cell-spacecraft="{ row }">
      <RouterLink
        v-if="row.sc"
        :to="to(row)"
        class="max-md:hit-44 whitespace-nowrap text-readout no-underline hover:text-bright hover:underline"
        >{{ row.sc.name }}</RouterLink
      >
      <span v-else class="text-text-3">{{ row.episode.spacecraft?.name ?? "Mission" }}</span>
    </template>
    <template #cell-point="{ row }">
      <span class="font-mono whitespace-nowrap text-readout">{{ row.episode.point.name }}</span>
      <span class="text-text-3">
        · {{ conditionWords(row.episode.source_state) ?? "out of limits" }}</span
      >
    </template>
    <template #cell-value="{ row }">
      <span :class="tint(row)">{{
        withUnit(formatValue(row.episode.last_value), row.episode.point.unit) ?? "—"
      }}</span>
      <span class="text-text-4">
        /
        {{
          withUnit(formatLimitLike(row.limit, row.episode.last_value), row.episode.point.unit) ??
          "—"
        }}</span
      >
    </template>
    <template #cell-since="{ row }">
      <time
        :datetime="row.episode.opened_at"
        :title="formatAbsolute(new Date(row.episode.opened_at))"
        >{{ formatCountdown(new Date(row.episode.opened_at), now) }}</time
      >
    </template>
    <template #cell-owner="{ row }">
      <span class="flex flex-col gap-0.5 font-mono text-xs uppercase">
        <span :class="row.owner === 'Unassigned' ? 'text-text-4' : 'text-text-2'">{{
          row.owner
        }}</span>
        <span class="text-text-3">{{
          row.episode.source === "catalog_monitoring" ? "Live" : "Ground limits"
        }}</span>
      </span>
    </template>
    <template #cell-contact="{ row }"
      ><span :class="row.sc?.in_contact ? 'text-readout' : 'text-text-3'">{{
        (row.sc && nextContact(row.sc, now)) ?? "—"
      }}</span></template
    >
  </ApTable>
</template>
