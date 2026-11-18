<script setup lang="ts">
import { RouterLink } from "vue-router";
import { formatCountdown, useNow, ApStatusMark } from "@/ui";
import { conditionWords } from "./api.ts";
import { formatLimitLike, formatValue, withUnit } from "./format.ts";
import { craftOrMission, type AlarmListRow } from "./list.ts";

/** Alarms under 768px: two lines (spacecraft + severity; point · condition · value / limit · opened · owner). */
defineProps<{ rows: readonly AlarmListRow[] }>();
defineEmits<{ toggle: [key: string] }>();
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
      <button
        v-if="row.group"
        type="button"
        class="flex min-h-11 w-full cursor-pointer items-center justify-between gap-3 border-0 bg-transparent p-0 text-left"
        :aria-expanded="row.group.expanded"
        @click="$emit('toggle', row.key)"
      >
        <span class="font-semibold text-readout"
          ><span aria-hidden="true" class="text-text-3">{{ row.group.expanded ? "▾" : "▸" }}</span>
          {{ row.episode.point.name }} ·
          {{ conditionWords(row.episode.source_state) ?? "out of limits" }}</span
        >
        <span class="text-md whitespace-nowrap text-text-3">{{ row.group.where }}</span>
      </button>
      <template v-else>
        <div
          class="flex min-h-11 items-center justify-between gap-3"
          :class="{ 'pl-4': row.member }"
        >
          <RouterLink
            v-if="row.sc"
            :to="{
              name: 'ops.spacecraft',
              params: { scId: row.sc.scid },
              query: { point: row.episode.point.id },
            }"
            class="inline-flex min-h-11 items-center font-semibold whitespace-nowrap text-readout no-underline"
            >{{ row.sc.name }}</RouterLink
          >
          <span v-else class="text-text-3">{{ craftOrMission(row.episode) }}</span>
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
              withUnit(
                formatLimitLike(row.limit, row.episode.last_value),
                row.episode.point.unit,
              ) ?? "—"
            }}</span
          >
          ·
          <span class="font-mono">{{ formatCountdown(new Date(row.episode.opened_at), now) }}</span>
          ·
          <span class="font-mono text-xs uppercase">{{ row.owner }}</span>
        </p>
      </template>
    </li>
  </ul>
</template>
