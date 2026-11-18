<script setup lang="ts">
import { RouterLink, type RouteLocationRaw } from "vue-router";
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
import { craftOrMission, type AlarmListRow } from "./list.ts";

/** L1 · Alarm episodes. The Spacecraft cell links to Investigate on that point (name-cell link). */
defineProps<{ rows: readonly AlarmListRow[] }>();
/** A group header's disclosure (identical point + condition across spacecraft). */
defineEmits<{ toggle: [key: string] }>();
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
/** A group row opens at its earliest member and contacts through its soonest (ux 784726fc). */
const openedAt = (row: AlarmListRow) => row.group?.openedAt ?? row.episode.opened_at;
const contactOf = (row: AlarmListRow) => (row.group ? row.group.soonest : row.sc);
const contactText = (row: AlarmListRow) => {
  const sc = contactOf(row);
  return (sc && nextContact(sc, now.value)) ?? "—";
};
/** Only rows with a spacecraft link (the template's v-else-if): no SCID, no link (§12C). */
const to = (row: AlarmListRow, sc: NonNullable<AlarmListRow["sc"]>): RouteLocationRaw => ({
  name: "ops.spacecraft",
  params: { scId: sc.scid, tab: "investigate" },
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
      <button
        v-if="row.group"
        type="button"
        class="max-md:hit-44 inline-flex cursor-pointer items-center gap-1.5 border-0 bg-transparent p-0 whitespace-nowrap text-readout hover:underline"
        :aria-expanded="row.group.expanded"
        @click="$emit('toggle', row.key)"
      >
        <span aria-hidden="true" class="text-text-3">{{ row.group.expanded ? "▾" : "▸" }}</span
        >{{ row.group.where }}
      </button>
      <RouterLink
        v-else-if="row.sc"
        :class="{ 'pl-5': row.member }"
        :to="to(row, row.sc)"
        class="max-md:hit-44 whitespace-nowrap text-readout no-underline hover:text-bright hover:underline"
        >{{ row.sc.name }}</RouterLink
      >
      <span v-else class="text-text-3">{{ craftOrMission(row.episode) }}</span>
    </template>
    <template #cell-point="{ row }">
      <span class="font-mono whitespace-nowrap text-readout">{{ row.episode.point.name }}</span>
      <span class="text-text-3">
        · {{ conditionWords(row.episode.source_state) ?? "out of limits" }}</span
      >
    </template>
    <template #cell-value="{ row }">
      <span v-if="row.group" class="text-text-2">{{ row.group.range ?? "" }}</span>
      <template v-else>
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
    </template>
    <template #cell-since="{ row }">
      <time :datetime="openedAt(row)" :title="formatAbsolute(new Date(openedAt(row)))">{{
        formatCountdown(new Date(openedAt(row)), now)
      }}</time>
    </template>
    <template #cell-owner="{ row }">
      <span v-if="row.group" class="font-mono text-xs text-text-3 uppercase">{{
        row.group.unassigned ? `${row.group.unassigned} unassigned` : "—"
      }}</span>
      <span v-else class="flex flex-col gap-0.5 font-mono text-xs uppercase">
        <span :class="row.owner === 'Unassigned' ? 'text-text-4' : 'text-text-2'">{{
          row.owner
        }}</span>
        <span class="text-text-3">{{
          row.episode.source === "catalog_monitoring" ? "Live" : "Ground limits"
        }}</span>
      </span>
    </template>
    <template #cell-contact="{ row }"
      ><span :class="contactOf(row)?.in_contact ? 'text-readout' : 'text-text-3'">{{
        contactText(row)
      }}</span></template
    >
  </ApTable>
</template>
