<script setup lang="ts">
import { computed } from "vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import type { WorkspacePlacement } from "../workspace/contracts";
import { fieldStats, inspectTable, toCsv } from "./inspect-data";

const props = defineProps<{ placement: WorkspacePlacement }>();
const stats = computed(() => fieldStats(props.placement));
const table = computed(() => inspectTable(props.placement));
const precision = computed(() => props.placement.widget?.options.precision ?? 2);
const fmt = (value: number | null) => (value === null ? "—" : value.toFixed(precision.value));

function download() {
  const blob = new Blob([toCsv(props.placement)], { type: "text/csv" });
  const url = URL.createObjectURL(blob);
  const link = Object.assign(document.createElement("a"), {
    href: url,
    download: `${props.placement.widget?.title || props.placement.authored_id}.csv`,
  });
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 0);
}
</script>

<template>
  <div class="space-y-4">
    <section v-if="stats.length" class="space-y-2">
      <span class="hud-label">Series statistics</span>
      <div class="overflow-x-auto">
        <table class="table table-xs w-full font-mono">
          <thead>
            <tr>
              <th>Field</th>
              <th>Count</th>
              <th>Min</th>
              <th>Max</th>
              <th>Mean</th>
              <th>Last</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in stats" :key="row.key">
              <td class="max-w-40 truncate">
                {{ row.name
                }}<span v-if="row.unit" class="text-base-content/60"> ({{ row.unit }})</span>
              </td>
              <td>{{ row.count }}</td>
              <td>{{ fmt(row.min) }}</td>
              <td>{{ fmt(row.max) }}</td>
              <td>{{ fmt(row.mean) }}</td>
              <td>{{ fmt(row.last) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    <section class="space-y-2">
      <div class="flex items-center justify-between gap-2">
        <span class="hud-label">Data · newest first</span>
        <CadenceButton size="xs" variant="outline" @click="download"
          ><CadenceIcon name="hero-arrow-down-tray" size="xs" />CSV</CadenceButton
        >
      </div>
      <div class="max-h-[60vh] overflow-auto">
        <table class="table table-xs w-full font-mono">
          <thead class="sticky top-0 bg-base-200">
            <tr>
              <th v-for="column in table.columns" :key="column.name">{{ column.name }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(row, index) in table.rows" :key="index">
              <td v-for="(value, column) in row" :key="column" class="whitespace-nowrap">
                {{ value }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p v-if="table.truncated" class="text-xs text-base-content/60">
        Showing the newest 500 rows. CSV includes all rows.
      </p>
    </section>
  </div>
</template>
