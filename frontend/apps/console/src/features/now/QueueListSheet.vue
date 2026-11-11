<script setup lang="ts">
import { nextTick, ref, shallowRef, useId } from "vue";
import { RouterLink } from "vue-router";
import { ApButton } from "@/ui";
import type { QueueItem } from "./queue.ts";

/**
 * A folded queue row's members (U37, the U30 sheet pattern): each links to its own drawer, and
 * following one closes the sheet.
 */
const dialog = ref<HTMLDialogElement | null>(null);
const item = shallowRef<QueueItem | null>(null);
const titleId = useId();
let opener: HTMLElement | null = null;
function open(row: QueueItem) {
  item.value = row;
  opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  dialog.value?.showModal();
  void nextTick(() => dialog.value?.querySelector<HTMLElement>("footer button")?.focus());
}
function onClosed() {
  opener?.focus();
  opener = null;
}
defineExpose({ open });
</script>

<template>
  <dialog
    ref="dialog"
    :aria-labelledby="titleId"
    aria-modal="true"
    class="m-auto w-[min(760px,calc(100vw-32px))] border border-line bg-panel p-0 text-readout backdrop:bg-[rgba(5,7,10,0.72)]"
    @close="onClosed"
  >
    <div class="flex max-h-[70vh] flex-col gap-3 overflow-auto p-5">
      <h2 :id="titleId" class="m-0 font-display text-xl font-semibold tracking-tag uppercase">
        {{ item?.list?.title ?? "" }}
      </h2>
      <ul class="m-0 flex list-none flex-col gap-2 p-0">
        <li
          v-for="row in item?.list?.rows ?? []"
          :key="row.key"
          class="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 border-t border-hairline pt-2"
        >
          <RouterLink
            :to="row.to"
            class="max-md:hit-44 font-mono text-sm text-readout tabular hover:underline"
            @click="dialog?.close()"
            >{{ row.text }}</RouterLink
          >
          <span v-if="row.detail" class="font-mono text-xs text-text-3">{{ row.detail }}</span>
        </li>
      </ul>
    </div>
    <footer class="flex items-center justify-end border-t border-hairline px-5 py-3">
      <ApButton variant="ghost" @click="dialog?.close()">Close</ApButton>
    </footer>
  </dialog>
</template>
