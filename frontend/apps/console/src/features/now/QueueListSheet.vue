<script setup lang="ts">
import { ref, shallowRef } from "vue";
import { RouterLink } from "vue-router";
import { ApButton, ApSheet } from "@/ui";
import type { QueueItem } from "./queue.ts";

/**
 * A folded queue row's members (U37, the U30 sheet pattern) on the kit ApSheet: each links to its
 * own drawer, and following one closes the sheet.
 */
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const item = shallowRef<QueueItem | null>(null);
function open(row: QueueItem) {
  item.value = row;
  sheet.value?.open();
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" :title="item?.list?.title ?? ''" width="wide">
    <ul class="m-0 flex list-none flex-col gap-2 p-0">
      <li
        v-for="row in item?.list?.rows ?? []"
        :key="row.key"
        class="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 border-t border-hairline pt-2"
      >
        <RouterLink
          :to="row.to"
          class="max-md:hit-44 font-mono text-sm text-readout tabular hover:underline"
          @click="sheet?.close()"
          >{{ row.text }}</RouterLink
        >
        <span v-if="row.detail" class="font-mono text-xs text-text-3">{{ row.detail }}</span>
      </li>
    </ul>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Close</ApButton>
    </template>
  </ApSheet>
</template>
