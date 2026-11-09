<script setup lang="ts">
import { RouterLink } from "vue-router";
import { formatCountdown, useNow, ApStatusMark } from "@/ui";
import { conditionWords } from "./api.ts";
import { formatLimitLike, formatValue, withUnit } from "./format.ts";
import type { AlarmListRow } from "./list.ts";

/** Alarms under 768px: two lines (spacecraft + severity; point · condition · value / limit · opened · owner). */
defineProps<{ rows: readonly AlarmListRow[] }>();
const now = useNow();
const tint = (row: AlarmListRow) =>
  row.episode.severity === "critical" ? "text-crit-text" : "text-caution-text";
</script>

<template>
  <ul class="m-0 list-none p-0" aria-label="Alarms">
    <li
      v-for="row in rows"
      :key="row.key"
      class="border-t border-hairline px-4 py-1 first:border-t-0"
    >
      <div class="flex min-h-11 items-center justify-between gap-3">
        <RouterLink
          v-if="row.sc"
          :to="{
            name: 'ops.spacecraft',
            params: { scId: String(row.sc.scid) },
            query: { point: row.episode.point.id },
          }"
          class="inline-flex min-h-11 items-center font-semibold whitespace-nowrap text-readout no-underline"
          >{{ row.sc.name }}</RouterLink
        >
        <span v-else class="text-text-3">{{ row.episode.spacecraft?.name ?? "Mission" }}</span>
        <span
          class="inline-flex items-center gap-2 text-md whitespace-nowrap capitalize"
          :class="tint(row)"
        >
          <ApStatusMark :state="row.episode.severity === 'critical' ? 'crit' : 'caution'" />{{
            row.episode.severity
          }}
        </span>
      </div>
      <p class="m-0 pb-1.5 text-md text-text-3">
        <span class="font-mono text-readout">{{ row.episode.point.name }}</span>
        · {{ conditionWords(row.episode.source_state) ?? "out of limits" }} ·
        <span class="font-mono" :class="tint(row)">{{
          withUnit(formatValue(row.episode.last_value), row.episode.point.unit) ?? "—"
        }}</span>
        <span class="font-mono text-text-4">
          /
          {{
            withUnit(formatLimitLike(row.limit, row.episode.last_value), row.episode.point.unit) ??
            "—"
          }}</span
        >
        ·
        <span class="font-mono">{{ formatCountdown(new Date(row.episode.opened_at), now) }}</span> ·
        <span class="font-mono text-xs uppercase">{{ row.owner }}</span>
      </p>
    </li>
  </ul>
</template>
