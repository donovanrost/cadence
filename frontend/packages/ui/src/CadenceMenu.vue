<script setup lang="ts">
import { DropdownMenuContent, DropdownMenuRoot, DropdownMenuTrigger } from "reka-ui";
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue";
import {
  announceCadencePopoverOpened,
  focusCurrentPopoverTrigger,
  preservesPopoverOpenState,
  subscribeToLegacyOverlayOpen,
} from "./popover_compatibility";

defineOptions({ inheritAttrs: false });

type MenuIdentity = string | null | undefined;

const props = withDefaults(
  defineProps<{
    identity: MenuIdentity;
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
let removeLegacyOverlayListener: (() => void) | null = null;

// CADENCE_MENU_FOCUS_POLICY_START
const createCadenceMenuFocusPolicy = () => {
  let suppressCloseAutoFocus = false;

  return {
    closeWithoutFocus() {
      suppressCloseAutoFocus = true;
    },
    restoreFocusOnClose() {
      const restoreFocus = !suppressCloseAutoFocus;
      suppressCloseAutoFocus = false;
      return restoreFocus;
    },
  };
};

const focusFirstCadenceMenuItem = (rootElement: HTMLElement | null) => {
  const firstItem = rootElement?.querySelector<HTMLElement>(
    "[data-overlay-panel] [role='menuitem']",
  );
  if (!firstItem || typeof firstItem.focus !== "function") return false;

  firstItem.focus();
  return true;
};
// CADENCE_MENU_FOCUS_POLICY_END

const focusPolicy = createCadenceMenuFocusPolicy();

const closeWithoutFocus = () => {
  if (!open.value) return;
  focusPolicy.closeWithoutFocus();
  open.value = false;
};

const updateOpen = async (nextOpen: boolean) => {
  if (nextOpen && (!props.identity || !root.value)) return;

  open.value = nextOpen;
  if (!nextOpen) return;

  await nextTick();
  if (!open.value || !root.value || root.value.id !== props.identity) {
    closeWithoutFocus();
    return;
  }

  announceCadencePopoverOpened(window, root.value);
  focusFirstCadenceMenuItem(root.value);
};

const restoreCurrentTriggerFocus = async () => {
  await nextTick();
  const currentRoot = root.value;
  if (!currentRoot) return;
  if (currentRoot.id !== props.identity) return;

  focusCurrentPopoverTrigger(currentRoot);
};

const handleCloseAutoFocus = (event: Event) => {
  const restoreFocus = focusPolicy.restoreFocusOnClose();
  event.preventDefault();
  if (restoreFocus) void restoreCurrentTriggerFocus();
};

const handleInteractOutside = (event: Event) => {
  const trigger = root.value?.querySelector<HTMLElement>(":scope > [data-overlay-trigger]");
  if (event.target instanceof Node && trigger?.contains(event.target)) return;
  focusPolicy.closeWithoutFocus();
};

const handleTabKeyDown = () => focusPolicy.closeWithoutFocus();
const handleItemSelect = () => focusPolicy.closeWithoutFocus();

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
  focusPolicy.closeWithoutFocus();
  open.value = false;
  removeLegacyOverlayListener?.();
  removeLegacyOverlayListener = null;
});
</script>

<template>
  <div ref="root" v-bind="$attrs" :data-overlay-open="open ? '' : undefined">
    <DropdownMenuRoot :open="open" :modal="false" @update:open="updateOpen">
      <DropdownMenuTrigger as-child>
        <slot name="trigger" :open="open"></slot>
      </DropdownMenuTrigger>

      <DropdownMenuContent
        v-if="open"
        as-child
        :side="props.side"
        :align="props.align"
        :side-offset="props.sideOffset"
        :collision-padding="props.collisionPadding"
        :prioritize-position="props.prioritizePosition"
        :loop="true"
        position-strategy="fixed"
        @close-auto-focus="handleCloseAutoFocus"
        @interact-outside="handleInteractOutside"
        @keydown.tab="handleTabKeyDown"
      >
        <slot name="content" :open="open" :onItemSelect="handleItemSelect"></slot>
      </DropdownMenuContent>
      <slot v-else name="content" :open="open" :onItemSelect="handleItemSelect"></slot>
    </DropdownMenuRoot>
  </div>
</template>
