<script setup lang="ts">
import { nextTick, ref, useId } from "vue";
import { focusFirstConnected } from "./lib/focus.ts";
import { useScrollable } from "./lib/scrollable.ts";

/**
 * A modal sheet on the native `<dialog>`: `showModal` gives the focus trap, Escape and the inert
 * page. Opening focuses `initialFocus` (default: the first footer button); closing returns focus
 * to whatever opened it. The title is the dialog's name; the body scrolls past 70vh so the footer
 * stays in view. A footer item with `mr-auto` sits on the left. Callers open and close it through the
 * exposed `open()` / `close()`; `closed` fires on every close (button, Escape or `close()`).
 * `placement="side"` is a 400px panel on the right, full height and NOT modal, so the page behind
 * stays usable (dashboards' widget sheet while editing); Escape still closes it.
 *
 * Below 768px (design-language §9) every sheet is full-height, edge to edge at 100dvh so it shrinks
 * with the on-screen keyboard: the title row (with a close ✕) pinned on top, the action row (full
 * width, 48px) pinned above the safe area, only the body scrolling between them. A side sheet is
 * modal there (the page can't sit beside it), so it traps focus and takes aria-modal. A long title
 * wraps on desktop and clamps to two lines on a phone, never a one-line ellipsis (lead).
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
    /**
     * ux a11y A5: where focus goes on close when the opener is gone (the action removed its row):
     * an element, or a function evaluated at close. Without it, the page's main heading.
     */
    returnFocus?: HTMLElement | (() => HTMLElement | null) | null | undefined;
    /**
     * ux a11y A1 exception: a danger sheet that opens on its Reason skips the consequence sentence,
     * so the dialog is described by it. The id of that sentence; absent, no aria-describedby.
     */
    describedBy?: string | undefined;
    /**
     * A detail sheet beside what it details (a11y A3): a side sheet showing the row or point picked
     * from a list or plot that stays on screen. Picking another one re-opens it (focus moves in, as
     * for any side sheet), and closing returns focus to the one picked last, not the first.
     */
    detail?: boolean | undefined;
  }>(),
  {
    width: "narrow",
    initialFocus: "footer button",
    placement: "center",
    dismissible: true,
    detail: false,
  },
);
const emit = defineEmits<{ closed: [] }>();
defineSlots<{ default(): unknown; footer?(): unknown }>();

const dialog = ref<HTMLDialogElement | null>(null);
const titleId = useId();
/** A body that scrolls is a named, focusable group (axe scrollable-region-focusable). */
const body = ref<HTMLElement | null>(null);
const scrolls = useScrollable(body);
let opener: HTMLElement | null = null;
/** Below md, as the shell's useSmallScreen; read on open (the kit can't import the shell). */
const PHONE = "(max-width: 47.99rem)";
const phone = () => typeof window.matchMedia === "function" && window.matchMedia(PHONE).matches;
/** Center sheets always; a side sheet when opened on a phone. */
const modal = ref(props.placement !== "side");

/** The caller's target, else the ✕ (a sheet with no footer has nothing else to land on, a11y A1). */
const focusInitial = () =>
  (
    dialog.value?.querySelector<HTMLElement>(props.initialFocus) ??
    dialog.value?.querySelector<HTMLElement>("[data-sheet-close]:not(.hidden)")
  )?.focus();
/** Already open (only a side sheet can be: its page stays usable), the opener moves focus back in (ux a11y A3). */
function open() {
  const active = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  if (!dialog.value?.open) {
    opener = active;
    modal.value = props.placement !== "side" || phone();
    if (modal.value) dialog.value?.showModal();
    else dialog.value?.show();
  } else if (props.detail && active && !dialog.value.contains(active)) {
    // A3: a detail sheet re-opened by another pick returns focus to that pick on close.
    opener = active;
  }
  void nextTick(focusInitial);
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
  if (!modal.value && event.key === "Escape" && props.dismissible) {
    event.stopPropagation();
    close();
  }
}
/** Back to the opener, else the caller's target, else the page's h1 (never <body>, A5). */
function onClose() {
  const fallback =
    typeof props.returnFocus === "function" ? props.returnFocus() : props.returnFocus;
  focusFirstConnected(opener, fallback);
  opener = null;
  emit("closed");
}
defineExpose({ open, close });
</script>

<template>
  <dialog
    ref="dialog"
    :aria-labelledby="titleId"
    :aria-describedby="describedBy"
    :aria-modal="modal ? 'true' : undefined"
    class="flex-col border border-line bg-panel p-0 text-readout open:flex max-md:inset-0 max-md:m-0 max-md:h-dvh max-md:max-h-none max-md:w-full max-md:max-w-none max-md:border-0"
    :class="
      placement === 'side'
        ? 'fixed inset-y-0 right-0 left-auto z-40 m-0 h-dvh max-h-none w-[min(400px,100vw)]'
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
    <header
      class="flex flex-none items-center gap-3 px-5 pt-5 max-md:min-h-12 max-md:border-b max-md:border-hairline max-md:py-1 max-md:pr-0 max-md:pl-4"
    >
      <h2
        :id="titleId"
        class="m-0 min-w-0 font-display text-xl font-semibold tracking-tag uppercase max-md:line-clamp-2"
      >
        {{ title }}
      </h2>
      <button
        v-if="dismissible"
        type="button"
        aria-label="Close"
        data-sheet-close
        class="ml-auto size-12 flex-none cursor-pointer items-center justify-center border-0 bg-transparent text-xl text-text-3 hover:text-readout md:-my-2 md:size-9"
        :class="$slots.footer ? 'hidden max-md:flex' : 'flex'"
        @click="close"
      >
        <span aria-hidden="true">✕</span>
      </button>
    </header>
    <div
      ref="body"
      class="flex flex-col gap-3 overflow-auto px-5 pt-3 pb-5 max-md:min-h-0 max-md:flex-1 max-md:px-4 max-md:pt-4"
      :class="placement === 'side' ? 'min-h-0 flex-1' : 'max-h-[70vh] max-md:max-h-none'"
      :tabindex="scrolls ? 0 : undefined"
      :role="scrolls ? 'group' : undefined"
      :aria-labelledby="scrolls ? titleId : undefined"
    >
      <slot />
    </div>
    <!-- Phone: buttons share the row at 48px, above the home indicator. -->
    <footer
      v-if="$slots.footer"
      class="flex flex-none flex-wrap items-center justify-end gap-2 border-t border-hairline px-5 py-3 max-md:px-4 max-md:pb-[calc(0.75rem+env(safe-area-inset-bottom))] max-md:[&_button]:h-12 max-md:[&>a]:h-12 max-md:[&>a]:flex-1 max-md:[&>button]:flex-1"
    >
      <slot name="footer" />
    </footer>
  </dialog>
</template>
