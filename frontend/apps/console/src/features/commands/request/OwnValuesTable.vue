<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton } from "@/ui";
import type { CommandArgument } from "../api.ts";
import type { Group } from "../groups/show.ts";
import { cellOf, rawEntries, tableArgs, type Override } from "./ownValues.ts";

/**
 * Own-values table under a command (ux, CommandFlow C2): Target · one column per argument, with
 * the unit. A value that differs from the shared one is weight 600, an equal one text-4, and one
 * the override leaves out reads "default". First 8 rows in target order, then Show all.
 */
const props = defineProps<{
  command: Group["commands"][number];
  overrides: readonly Override[];
  args: readonly CommandArgument[];
  nameOf: (spacecraftId: string) => string;
}>();
const FIRST = 8;
const all = ref(false);
const names = computed(() => tableArgs(props.command, props.overrides));
const shared = computed(() => rawEntries(props.command.argument_values_json));
const argOf = (name: string) => props.args.find((a) => a.name === name);
const rows = computed(() => (all.value ? props.overrides : props.overrides.slice(0, FIRST)));
</script>

<template>
  <div class="flex flex-col gap-1">
    <table class="w-full border-collapse font-mono text-sm">
      <thead>
        <tr class="text-left text-xs text-text-3 uppercase">
          <th class="py-1 pr-3 font-normal">Target</th>
          <th v-for="n in names" :key="n" class="py-1 pr-3 font-normal">
            {{ n }}<template v-if="argOf(n)?.unit"> ({{ argOf(n)?.unit }})</template>
          </th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="o in rows" :key="o.spacecraftId" class="border-t border-hairline-faint">
          <td class="py-1 pr-3 text-readout">{{ nameOf(o.spacecraftId) }}</td>
          <td v-for="n in names" :key="n" class="py-1 pr-3 align-top">
            <span
              :class="
                cellOf(o, n, shared, argOf(n)).caution
                  ? 'text-caution-text'
                  : cellOf(o, n, shared, argOf(n)).kind === 'differs'
                    ? 'font-semibold text-readout'
                    : 'text-text-4'
              "
              :title="cellOf(o, n, shared, argOf(n)).caution ?? undefined"
              >{{ cellOf(o, n, shared, argOf(n)).text }}</span
            >
          </td>
        </tr>
      </tbody>
    </table>
    <ApButton
      v-if="!all && overrides.length > FIRST"
      size="compact"
      variant="ghost"
      class="self-start"
      @click="all = true"
      >Show all {{ overrides.length }}</ApButton
    >
  </div>
</template>
