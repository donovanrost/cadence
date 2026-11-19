<script setup lang="ts">
import { computed } from "vue";
import { lineDiff } from "./json-diff.ts";

/** Two versions' JSON as a unified diff: + and − marks carry the meaning, not color. */
const props = defineProps<{ before: string; after: string }>();
const lines = computed(() => lineDiff(props.before, props.after));
const mark = { same: " ", added: "+", removed: "−" } as const;
const tone = {
  same: "text-text-3",
  added: "text-readout bg-[var(--apogee-wash-action)]",
  removed: "text-text-4 line-through",
} as const;
</script>

<template>
  <div
    class="max-h-[60vh] overflow-auto border border-hairline bg-vacuum font-mono text-xs"
    tabindex="0"
    aria-label="JSON changes"
  >
    <table class="w-full border-collapse">
      <tbody>
        <tr v-for="(line, index) in lines" :key="index">
          <td v-if="line.kind === 'gap'" colspan="4" class="bg-panel px-2 py-0.5 text-text-4">
            ⋯ {{ line.hidden }} unchanged {{ line.hidden === 1 ? "line" : "lines" }}
          </td>
          <template v-else>
            <td class="w-10 select-none px-1 text-right text-text-4">{{ line.left ?? "" }}</td>
            <td class="w-10 select-none px-1 text-right text-text-4">{{ line.right ?? "" }}</td>
            <td class="w-4 select-none text-center" :class="tone[line.kind]">
              {{ mark[line.kind] }}
            </td>
            <td class="whitespace-pre px-1" :class="tone[line.kind]">{{ line.text }}</td>
          </template>
        </tr>
      </tbody>
    </table>
  </div>
</template>
