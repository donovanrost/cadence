<script setup lang="ts">
import { computed } from "vue";
import { ApStatusMark, stateTextClass } from "@/ui";
import type { WorkspacePlacement } from "../model/snapshot.ts";
import { limitLabel, limitMark, table, widgetTitle } from "../model/widget-data.ts";

/** Data table / status matrix. Limit-state cells carry their mark, not just a tint. */
const props = defineProps<{ placement: WorkspacePlacement }>();
const data = computed(() => table(props.placement));
const name = computed(() => widgetTitle(props.placement));
</script>

<template>
  <!-- B1: the scroll box is a tab stop named by its widget, and the table has a caption. -->
  <div class="h-full min-h-0 overflow-auto" role="region" tabindex="0" :aria-label="name">
    <table class="w-full border-collapse text-md">
      <caption class="sr-only" v-text="name" />
      <thead class="sticky top-0 bg-panel">
        <tr>
          <th
            v-for="column in data.columns"
            :key="column.key"
            scope="col"
            class="whitespace-nowrap border-b border-hairline px-2 py-1.5 text-left font-display text-xs uppercase tracking-btn text-text-4"
          >
            {{ column.label }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="row in data.rows" :key="row.key" class="hover:bg-raised">
          <td
            v-for="cell in row.cells"
            :key="cell.key"
            class="whitespace-nowrap border-b border-hairline-faint px-2 py-1 font-mono tabular-nums"
            :class="cell.state ? stateTextClass(limitMark[cell.state]) : 'text-readout'"
          >
            <span class="inline-flex items-center gap-1.5">
              <ApStatusMark v-if="cell.state" :state="limitMark[cell.state]" />{{ cell.text
              }}<span v-if="cell.state" class="sr-only">, {{ limitLabel[cell.state] }}</span>
            </span>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
