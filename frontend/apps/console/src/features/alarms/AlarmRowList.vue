<script setup lang="ts">
import { RouterLink } from "vue-router";
import { formatCountdown, useNow, ApStatusMark } from "@/ui";
import { conditionWords, crossedCondition } from "./api.ts";
import { formatLimitLike, formatValue, withUnit } from "./format.ts";
import type { AlarmListRow } from "./list.ts";

/**
 * Alarms under 768px (two lines, like Fleet; ux pass 1 #3): spacecraft link + severity, then
 * point · condition · value / limit · first crossed. Ids never wrap.
 */
defineProps<{ rows: readonly AlarmListRow[] }>();
const now = useNow();
const tint = (row: AlarmListRow) =>
  row.alarm.severity === "critical"
    ? "text-crit-text"
    : row.alarm.severity === "caution"
      ? "text-caution-text"
      : "text-text-2";
const mark = (row: AlarmListRow) =>
  row.alarm.severity === "critical"
    ? "crit"
    : row.alarm.severity === "caution"
      ? "caution"
      : "nominal";
</script>

<template>
  <ul class="m-0 list-none p-0" aria-label="Active alarms">
    <li
      v-for="row in rows"
      :key="row.alarm.id"
      class="border-t border-hairline px-4 py-1 first:border-t-0"
    >
      <div class="flex min-h-11 items-center justify-between gap-3">
        <RouterLink
          v-if="row.sc"
          :to="{
            name: 'ops.spacecraft',
            params: { scId: String(row.sc.scid) },
            query: { alarm: row.alarm.id },
          }"
          class="inline-flex min-h-11 items-center font-semibold whitespace-nowrap text-readout no-underline"
          >{{ row.sc.name }}</RouterLink
        >
        <span v-else class="text-text-3">Mission</span>
        <span
          class="inline-flex items-center gap-2 text-md whitespace-nowrap capitalize"
          :class="tint(row)"
        >
          <ApStatusMark :state="mark(row)" />{{ row.alarm.severity }}
        </span>
      </div>
      <p class="m-0 pb-1.5 text-md text-text-3">
        <span class="font-mono text-readout">{{ row.alarm.point.name }}</span>
        · {{ conditionWords(crossedCondition(row.alarm)) ?? "out of limits" }} ·
        <span class="font-mono" :class="tint(row)">{{
          withUnit(formatValue(row.alarm.value), row.alarm.point.unit) ?? "—"
        }}</span>
        <span class="font-mono text-text-4">
          /
          {{
            withUnit(formatLimitLike(row.limit, row.alarm.value), row.alarm.point.unit) ?? "—"
          }}</span
        >
        <template v-if="row.alarm.first_crossed_at">
          ·
          <span class="font-mono">{{
            formatCountdown(new Date(row.alarm.first_crossed_at), now)
          }}</span></template
        >
      </p>
    </li>
  </ul>
</template>
