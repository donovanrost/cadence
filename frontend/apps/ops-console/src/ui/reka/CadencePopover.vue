<script setup lang="ts">
import { PopoverContent, PopoverRoot, PopoverTrigger } from "reka-ui";
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue";
import {
  announceCadencePopoverOpened,
  focusCurrentPopoverTrigger,
  preservesPopoverOpenState,
  subscribeToLegacyOverlayOpen,
} from "./popover_compatibility.js";

defineOptions({ inheritAttrs: false });

type PopoverIdentity = string | null | undefined;

const props = withDefaults(
  defineProps<{
    identity: PopoverIdentity;
    side?: "top" | "right" | "bottom" | "left";
    align?: "start" | "center" | "end";
    sideOffset?: number;
    collisionPadding?: number;
    prioritizePosition?: boolean;
  }>(),
  {
    side: "bottom",
    align: "end",
    sideOffset: 8,
    collisionPadding: 16,
    prioritizePosition: true,
  },
);

const root = ref<HTMLElement | null>(null);
const open = ref(false);
let suppressCloseAutoFocus = false;
let suppressEscapeDismiss = false;
let removeLegacyOverlayListener: (() => void) | null = null;

const closeWithoutFocus = () => {
  if (!open.value) return;
  suppressCloseAutoFocus = true;
  open.value = false;
};

const updateOpen = async (nextOpen: boolean) => {
  if (nextOpen && (!props.identity || !root.value)) return;

  if (!nextOpen && suppressEscapeDismiss) {
    suppressEscapeDismiss = false;
    open.value = true;
    return;
  }

  open.value = nextOpen;
  if (!nextOpen) return;

  await nextTick();
  if (!open.value || !root.value || root.value.id !== props.identity) {
    closeWithoutFocus();
    return;
  }

  announceCadencePopoverOpened(window, root.value);
};

const restoreCurrentTriggerFocus = async () => {
  await nextTick();
  const currentRoot = root.value;
  if (!currentRoot) return;
  if (currentRoot.id !== props.identity) return;

  focusCurrentPopoverTrigger(currentRoot);
};

const handleCloseAutoFocus = (event: Event) => {
  const restoreFocus = !suppressCloseAutoFocus;
  event.preventDefault();
  suppressCloseAutoFocus = false;
  if (restoreFocus) void restoreCurrentTriggerFocus();
};

const handleInteractOutside = (event: Event) => {
  const trigger = root.value?.querySelector<HTMLElement>(":scope > [data-overlay-trigger]");
  if (event.target instanceof Node && trigger?.contains(event.target)) return;
  event.preventDefault();
  closeWithoutFocus();
};

const handleEscapeKeyDown = (event: Event) => {
  if (root.value?.querySelector("[data-overlay-open]")) suppressEscapeDismiss = true;
};

watch(
  () => props.identity,
  (nextIdentity, previousIdentity) => {
    if (!preservesPopoverOpenState(open.value, previousIdentity, nextIdentity)) {
      closeWithoutFocus();
    }
  },
);

onMounted(() => {
  if (!root.value) return;
  removeLegacyOverlayListener = subscribeToLegacyOverlayOpen(window, root.value, closeWithoutFocus);
});

onBeforeUnmount(() => {
  suppressCloseAutoFocus = true;
  suppressEscapeDismiss = false;
  open.value = false;
  removeLegacyOverlayListener?.();
  removeLegacyOverlayListener = null;
});
</script>

<template>
  <div ref="root" v-bind="$attrs" :data-overlay-open="open ? '' : undefined">
    <PopoverRoot :open="open" :modal="false" @update:open="updateOpen">
      <PopoverTrigger as-child>
        <slot name="trigger" :open="open"></slot>
      </PopoverTrigger>

      <PopoverContent
        v-if="open"
        as-child
        :side="props.side"
        :align="props.align"
        :side-offset="props.sideOffset"
        :collision-padding="props.collisionPadding"
        :prioritize-position="props.prioritizePosition"
        position-strategy="fixed"
        sticky="always"
        @close-auto-focus="handleCloseAutoFocus"
        @interact-outside="handleInteractOutside"
        @escape-key-down="handleEscapeKeyDown"
      >
        <slot name="content" :open="open"></slot>
      </PopoverContent>
      <slot v-else name="content" :open="open"></slot>
    </PopoverRoot>
  </div>
</template>
