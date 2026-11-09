<script setup lang="ts">
import { nextTick, ref } from "vue";
import { ApButton } from "@/ui";
import type { UnconfirmedPass } from "./unconfirmed.ts";

/**
 * Every unconfirmed pass (ux U30 cap: the callout shows the soonest 5). The `row-actions` slot is
 * the callout's, passed through, so U32's actions sit on these rows too (fe-setup).
 */
defineProps<{ title: string; passes: readonly UnconfirmedPass[] }>();
defineSlots<{ "row-actions"?: (props: { pass: UnconfirmedPass }) => unknown }>();
const dialog = ref<HTMLDialogElement | null>(null);
const titleId = `ap-unconfirmed-${Math.random().toString(36).slice(2, 9)}`;
let opener: HTMLElement | null = null;
function open() {
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
        {{ title }}
      </h2>
      <ul class="m-0 flex list-none flex-col gap-2 p-0">
        <li
          v-for="pass in passes"
          :key="pass.snapshot_id"
          class="flex flex-wrap items-center gap-x-3 gap-y-1 border-t border-hairline pt-2"
        >
          <span class="font-mono text-sm text-text-2 tabular">{{ pass.text }}</span>
          <span class="font-mono text-xs text-text-3">{{ pass.provider.name ?? "" }}</span>
          <slot name="row-actions" :pass="pass" />
        </li>
      </ul>
    </div>
    <footer class="flex items-center justify-end border-t border-hairline px-5 py-3">
      <ApButton variant="ghost" @click="dialog?.close()">Close</ApButton>
    </footer>
  </dialog>
</template>
