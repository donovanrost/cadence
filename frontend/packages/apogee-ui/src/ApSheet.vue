<script setup lang="ts">
import { nextTick, ref, useId } from "vue";

/**
 * A modal sheet on the native `<dialog>`: `showModal` gives the focus trap, Escape and the inert
 * page. Opening focuses `initialFocus` (default: the first footer button); closing returns focus
 * to whatever opened it. The title is the dialog's name; the body scrolls past 70vh so the footer
 * stays in view. A footer item with `mr-auto` sits on the left. Callers open and close it through the
 * exposed `open()` / `close()`; `closed` fires on every close (button, Escape or `close()`).
 */
const props = withDefaults(
  defineProps<{
    title: string;
    /** `narrow` 560px for a decision, `wide` 760px for a list. */
    width?: "narrow" | "wide" | undefined;
    /** Selector inside the sheet to focus on open. */
    initialFocus?: string | undefined;
  }>(),
  { width: "narrow", initialFocus: "footer button" },
);
const emit = defineEmits<{ closed: [] }>();
defineSlots<{ default(): unknown; footer?(): unknown }>();

const dialog = ref<HTMLDialogElement | null>(null);
const titleId = useId();
let opener: HTMLElement | null = null;

function open() {
  if (dialog.value?.open) return;
  opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  dialog.value?.showModal();
  void nextTick(() => dialog.value?.querySelector<HTMLElement>(props.initialFocus)?.focus());
}
function close() {
  dialog.value?.close();
}
function onClose() {
  opener?.focus();
  opener = null;
  emit("closed");
}
defineExpose({ open, close });
</script>

<template>
  <dialog
    ref="dialog"
    :aria-labelledby="titleId"
    aria-modal="true"
    class="m-auto border border-line bg-panel p-0 text-readout backdrop:bg-[rgba(5,7,10,0.72)]"
    :class="
      width === 'wide' ? 'w-[min(760px,calc(100vw-32px))]' : 'w-[min(560px,calc(100vw-32px))]'
    "
    @close="onClose"
  >
    <div class="flex max-h-[70vh] flex-col gap-3 overflow-auto p-5">
      <h2 :id="titleId" class="m-0 font-display text-xl font-semibold tracking-tag uppercase">
        {{ title }}
      </h2>
      <slot />
    </div>
    <footer
      v-if="$slots.footer"
      class="flex flex-wrap items-center justify-end gap-2 border-t border-hairline px-5 py-3"
    >
      <slot name="footer" />
    </footer>
  </dialog>
</template>
