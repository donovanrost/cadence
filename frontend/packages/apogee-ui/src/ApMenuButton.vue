<script setup lang="ts">
import { provide, ref, useId } from "vue";
import { apMenuKey, useMenuButton } from "./menu-button.ts";

/**
 * A menu button (design-language §6): the trigger plus its role="menu" popup. Put ApMenuItem in the
 * default slot; anything else in the menu (a heading, a group label, a form around a submit item)
 * takes role="none".
 */
const props = withDefaults(
  defineProps<{
    /** The trigger's accessible name ("More dashboard actions", "MR, account menu for …"). */
    label: string;
    /** The menu's name, when it differs from the trigger's. */
    menuLabel?: string | undefined;
    /** Replaces the default 32px `⋯` trigger styling. */
    triggerClass?: string | undefined;
    /** Width of the popup (default min 200px). */
    menuClass?: string | undefined;
    /** Which edge of the trigger the popup lines up with. */
    align?: "start" | "end";
  }>(),
  { align: "end" },
);
defineSlots<{
  /** The trigger's content (default `⋯`). */
  trigger?: (scope: { open: boolean }) => unknown;
  /** The items. `dismiss` closes the menu and returns focus to the trigger. */
  default?: (scope: { dismiss: () => void }) => unknown;
}>();
const root = ref<HTMLElement | null>(null);
const trigger = ref<HTMLButtonElement | null>(null);
const { open, toggle, close, dismiss, onTriggerKey, onMenuKey } = useMenuButton(root, trigger);
const menuId = useId();
provide(apMenuKey, { dismiss });
defineExpose({ close, dismiss });
const defaultTrigger =
  "h-8 w-9 cursor-pointer border border-line bg-raised font-mono text-base text-readout hover:bg-raised-hi max-md:hit-44";
</script>

<template>
  <div ref="root" class="relative">
    <button
      ref="trigger"
      type="button"
      :class="props.triggerClass ?? defaultTrigger"
      :aria-label="label"
      :aria-expanded="open"
      aria-haspopup="menu"
      :aria-controls="menuId"
      @click="toggle"
      @keydown="onTriggerKey"
    >
      <slot name="trigger" :open="open">⋯</slot>
    </button>
    <div
      v-if="open"
      :id="menuId"
      role="menu"
      :aria-label="menuLabel ?? label"
      :class="[
        'absolute top-full z-30 border border-line bg-raised py-1.5',
        align === 'start' ? 'left-0' : 'right-0',
        props.menuClass ?? 'min-w-[200px]',
      ]"
      @keydown="onMenuKey"
    >
      <slot :dismiss="dismiss" />
    </div>
  </div>
</template>
