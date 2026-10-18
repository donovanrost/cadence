<script setup lang="ts">
import { computed } from "vue";
import { lineDiff } from "./json-diff";

const props = defineProps<{ before: string; after: string }>();
const lines = computed(() => lineDiff(props.before, props.after));
const tone = {
  added: "bg-success/10 text-success",
  removed: "bg-error/10 text-error",
  same: "text-base-content/70",
} as const;
const mark = { added: "+", removed: "−", same: " " } as const;
</script>

<template>
  <div class="max-h-[60vh] overflow-auto rounded-sm border border-base-300/60 font-mono text-xs">
    <table class="w-full border-collapse">
      <tbody>
        <tr v-for="(line, index) in lines" :key="index">
          <td
            v-if="line.kind === 'gap'"
            colspan="4"
            class="bg-base-300/30 px-2 py-0.5 text-base-content/60"
          >
            ⋯ {{ line.hidden }} unchanged {{ line.hidden === 1 ? "line" : "lines" }}
          </td>
          <template v-else>
            <td class="w-10 select-none px-1 text-right text-base-content/40">
              {{ line.left ?? "" }}
            </td>
            <td class="w-10 select-none px-1 text-right text-base-content/40">
              {{ line.right ?? "" }}
            </td>
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
