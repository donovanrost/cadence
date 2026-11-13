<script setup lang="ts">
import { nextTick, ref, useId } from "vue";
import { useScrollable } from "./lib/scrollable.ts";

/**
 * A modal sheet on the native `<dialog>`: `showModal` gives the focus trap, Escape and the inert
 * page. Opening focuses `initialFocus` (default: the first footer button); closing returns focus
 * to whatever opened it. The title is the dialog's name; the body scrolls past 70vh so the footer
 * stays in view. A footer item with `mr-auto` sits on the left. Callers open and close it through the
 * exposed `open()` / `close()`; `closed` fires on every close (button, Escape or `close()`).
 * `placement="side"` is a 400px panel on the right, full height and NOT modal, so the page behind
 * stays usable (dashboards' widget sheet while editing); Escape still closes it.
 */
const props = withDefaults(
  defineProps<{
    title: string;
    /** `narrow` 560px for a decision, `wide` 760px for a list. */
    width?: "narrow" | "wide" | undefined;
    /** Selector inside the sheet to focus on open. */
    initialFocus?: string | undefined;
    /** `center` (modal, the default) or `side` (400px, right-anchored, non-modal). */
    placement?: "center" | "side" | undefined;
    /** False: Escape doesn't close it; only the caller's own close() does (e.g. a show-once secret). */
    dismissible?: boolean | undefined;
  }>(),
  { width: "narrow", initialFocus: "footer button", placement: "center", dismissible: true },
);
const emit = defineEmits<{ closed: [] }>();
defineSlots<{ default(): unknown; footer?(): unknown }>();

const dialog = ref<HTMLDialogElement | null>(null);
const titleId = useId();
/** A body that scrolls is a named, focusable group (axe scrollable-region-focusable). */
const body = ref<HTMLElement | null>(null);
const scrolls = useScrollable(body);
let opener: HTMLElement | null = null;

function open() {
  if (dialog.value?.open) return;
  opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  if (props.placement === "side") dialog.value?.show();
  else dialog.value?.showModal();
  void nextTick(() => dialog.value?.querySelector<HTMLElement>(props.initialFocus)?.focus());
}
function close() {
  dialog.value?.close();
}
/** A modal dialog's Escape fires `cancel`; a non-dismissible sheet refuses it. */
function onCancel(event: Event) {
  if (!props.dismissible) event.preventDefault();
}
/** A non-modal dialog gets no native Escape; the side sheet adds it. */
function onKeydown(event: KeyboardEvent) {
  if (props.placement === "side" && event.key === "Escape" && props.dismissible) {
    event.stopPropagation();
    close();
  }
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
    :aria-modal="placement === 'side' ? undefined : 'true'"
    class="border border-line bg-panel p-0 text-readout"
    :class="
      placement === 'side'
        ? 'fixed inset-y-0 right-0 left-auto z-40 m-0 h-dvh max-h-none w-[min(400px,100vw)] flex-col open:flex'
        : [
            'm-auto backdrop:bg-[rgba(5,7,10,0.72)]',
            width === 'wide'
              ? 'w-[min(760px,calc(100vw-32px))]'
              : 'w-[min(560px,calc(100vw-32px))]',
          ]
    "
    @close="onClose"
    @cancel="onCancel"
    @keydown="onKeydown"
  >
    <div
      ref="body"
      class="flex flex-col gap-3 overflow-auto p-5"
      :class="placement === 'side' ? 'min-h-0 flex-1' : 'max-h-[70vh]'"
      :tabindex="scrolls ? 0 : undefined"
      :role="scrolls ? 'group' : undefined"
      :aria-labelledby="scrolls ? titleId : undefined"
    >
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
