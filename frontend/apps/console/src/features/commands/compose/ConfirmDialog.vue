<script setup lang="ts">
import { nextTick, ref, useId } from "vue";
import { ApButton } from "@/ui";

/**
 * The console's confirm pattern (as ReleasePass): a modal question with a danger action and a
 * way back. `ask()` resolves true for the action, false for cancel, Escape or a backdrop close.
 */
defineProps<{ question: string; body?: string | undefined; confirm: string; cancel: string }>();
const dialog = ref<HTMLDialogElement | null>(null);
const titleId = useId();
let settle: ((ok: boolean) => void) | null = null;

function ask(): Promise<boolean> {
  settle?.(false);
  dialog.value?.showModal();
  void nextTick(() => dialog.value?.querySelector<HTMLElement>("footer button")?.focus());
  return new Promise((resolve) => (settle = resolve));
}
function answer(ok: boolean) {
  const s = settle;
  settle = null;
  dialog.value?.close();
  s?.(ok);
}
defineExpose({ ask });
</script>

<template>
  <dialog
    ref="dialog"
    :aria-labelledby="titleId"
    aria-modal="true"
    class="m-auto w-[min(560px,calc(100vw-32px))] border border-line bg-panel p-0 text-readout backdrop:bg-[rgba(5,7,10,0.72)]"
    @close="answer(false)"
  >
    <div class="flex flex-col gap-3 p-5">
      <h2 :id="titleId" class="m-0 font-display text-xl font-semibold tracking-tag uppercase">
        {{ question }}
      </h2>
      <p v-if="body" class="m-0 text-text-2">{{ body }}</p>
    </div>
    <footer class="flex items-center justify-end gap-2 border-t border-hairline px-5 py-3">
      <ApButton variant="ghost" @click="answer(false)">{{ cancel }}</ApButton>
      <ApButton variant="danger" @click="answer(true)">{{ confirm }}</ApButton>
    </footer>
  </dialog>
</template>
