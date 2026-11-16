<script lang="ts">
/** The open confirm on the page (module scope, shared by every instance): one at a time. */
let openConfirm: { cancel: () => void } | null = null;
</script>

<script setup lang="ts">
import { nextTick, onBeforeUnmount, ref, useId, watch } from "vue";
import ApButton from "./ApButton.vue";
import { focusFirstConnected } from "./lib/focus.ts";

/**
 * An in-place confirm for one object whose result shows in place (design-language §7,
 * c9518231d). Several fields, a list of consequences or type-to-confirm stay sheets.
 * - Look: the info callout (raised, no status mark, no wash). The sentence (question plus
 *   consequence) and the danger button carry the danger. The action is a verb plus its object.
 * - Order: Cancel, then the action, right-aligned. On a phone they share a 48px row and stack in
 *   the same order when a label doesn't fit.
 * - Focus: on open, the first field (a reason) if there is one, else Cancel, never the action
 *   (A1). Esc does what Cancel does (A4). Cancel, and closing after the action, return focus to
 *   the trigger, else the caller's `returnFocus`, else the page h1 (A5). It isn't a trap: Tab
 *   may leave and it stays open.
 * - The trigger slot gets aria-expanded, aria-controls and the click that opens it.
 * - One open at a time: opening another cancels this one.
 * - A refusal is a line under the sentence in a polite live region; focus stays, and the confirm
 *   stays open for Cancel or a retry.
 */
const props = withDefaults(
  defineProps<{
    /** The action button: a verb plus its object ('Remove account'), never OK/Yes/Confirm. */
    action: string;
    /** The safe button's label when the screen has its own word ('Keep running'). */
    cancelLabel?: string | undefined;
    /** False for an action that isn't destructive (primary instead of danger). */
    danger?: boolean | undefined;
    busy?: boolean | undefined;
    /** The action's reason while busy, e.g. 'Removing…'. */
    busyReason?: string | undefined;
    /** Why the action can't run yet (e.g. 'Give a reason first.'); null when it can. */
    blocked?: string | null | undefined;
    /** The server's refusal, read politely under the sentence. */
    refusal?: string | null | undefined;
    /** Where focus goes when the trigger is gone after the action (the row's new state line). */
    returnFocus?: HTMLElement | (() => HTMLElement | null) | null | undefined;
  }>(),
  {
    cancelLabel: "Cancel",
    danger: true,
    busy: false,
    busyReason: "Working…",
    blocked: null,
    refusal: null,
  },
);
const emit = defineEmits<{ confirm: []; cancel: [] }>();
defineSlots<{
  default(): unknown;
  /** Optional: a confirm opened from a ⋯ menu item opens through v-model:open instead. */
  trigger?(props: {
    attrs: {
      "aria-expanded": "true" | "false";
      "aria-controls": string;
      onClick: (e: MouseEvent) => void;
    };
  }): unknown;
  fields?(): unknown;
}>();
/** Open state; the caller closes it after a successful action (`open = false`). */
const open = defineModel<boolean>("open", { default: false });
const id = useId();
const panel = ref<HTMLElement | null>(null);
let trigger: HTMLElement | null = null;

/** Closing because another confirm opened leaves focus where the user put it. */
let restoreFocus = true;
const self = { cancel: () => cancel(false) };

function start(event: MouseEvent) {
  if (open.value) return;
  trigger = event.currentTarget instanceof HTMLElement ? event.currentTarget : null;
  open.value = true;
}
/**
 * Opened by the trigger slot, or by the caller through v-model:open (e.g. from a ⋯ menu item,
 * whose menu hands focus back to its ⋯ first): then the focused element is the return target.
 */
watch(open, async (now, was) => {
  if (now && !was) {
    if (!trigger && document.activeElement instanceof HTMLElement) trigger = document.activeElement;
    if (openConfirm && openConfirm !== self) openConfirm.cancel();
    openConfirm = self;
  }
  await nextTick();
  if (now && !was) {
    const field = panel.value?.querySelector<HTMLElement>("input, textarea, select");
    (field ?? panel.value?.querySelector<HTMLElement>("[data-inline-cancel]"))?.focus();
  } else if (!now && was && restoreFocus) {
    const fallback =
      typeof props.returnFocus === "function" ? props.returnFocus() : props.returnFocus;
    focusFirstConnected(trigger, fallback);
  }
  if (!now) {
    if (openConfirm === self) openConfirm = null;
    trigger = null;
  }
  restoreFocus = true;
});
function cancel(returnFocusToTrigger = true) {
  if (!open.value) return;
  restoreFocus = returnFocusToTrigger;
  open.value = false;
  emit("cancel");
}
function onKeydown(event: KeyboardEvent) {
  if (event.key !== "Escape") return;
  event.stopPropagation();
  cancel();
}
onBeforeUnmount(() => {
  if (openConfirm === self) openConfirm = null;
});
</script>

<template>
  <slot
    name="trigger"
    :attrs="{ 'aria-expanded': open ? 'true' : 'false', 'aria-controls': id, onClick: start }"
  />
  <div
    v-if="open"
    :id="id"
    ref="panel"
    role="group"
    :aria-labelledby="`${id}-q`"
    class="flex w-full basis-full flex-col gap-3 bg-raised px-4 py-3 text-base text-readout"
    @keydown="onKeydown"
  >
    <div class="flex flex-col">
      <p :id="`${id}-q`" class="m-0"><slot /></p>
      <!-- Always displayed (an empty region has no height) so a refusal is announced. -->
      <p aria-live="polite" class="m-0 mt-1 text-sm text-caution-text empty:mt-0">
        {{ refusal ?? "" }}
      </p>
    </div>
    <slot name="fields" />
    <div
      class="flex flex-wrap items-center justify-end gap-2 max-md:[&>button]:h-12 max-md:[&>button]:flex-1"
    >
      <ApButton size="compact" variant="secondary" data-inline-cancel @click="cancel()">{{
        cancelLabel
      }}</ApButton>
      <ApButton
        size="compact"
        :variant="danger ? 'danger' : 'primary'"
        :disabled="busy || blocked !== null"
        :disabled-reason="busy ? busyReason : (blocked ?? undefined)"
        @click="emit('confirm')"
        >{{ action }}</ApButton
      >
    </div>
  </div>
</template>
