<script setup lang="ts">
import { computed, inject, useId } from "vue";
import { RouterLink, type RouteLocationRaw } from "vue-router";
import { apMenuKey } from "./menu-button.ts";

/**
 * One item of an ApMenuButton. Choosing it closes the menu and returns focus to the trigger first
 * (so a sheet it opens hands focus back there), then emits `select` (or follows `to`, or submits).
 * A disabled item stays focusable and is described by its reason (design-language §6); activating
 * it does nothing.
 */
const props = withDefaults(
  defineProps<{
    /** Why the item can't run now, shown on it. Unset: the item is enabled. */
    disabled?: string | undefined;
    /** Renders a RouterLink when set (and enabled). */
    to?: RouteLocationRaw | undefined;
    /** `submit` for an item that submits the form around it (Sign out). */
    type?: "button" | "submit";
  }>(),
  { type: "button" },
);
const emit = defineEmits<{ select: [] }>();
const menu = inject(apMenuKey, null);
const whyId = useId();
const itemClass = computed(() => [
  // The kit's :focus-visible outline (apogee.css), drawn inside so the next item can't cover it.
  "flex h-10 w-full items-center border-0 bg-transparent px-3.5 text-left text-base no-underline focus:bg-raised-hi focus-visible:-outline-offset-2",
  props.disabled === undefined
    ? "cursor-pointer text-readout hover:bg-raised-hi"
    : "cursor-default text-text-4",
]);
function choose(event: MouseEvent) {
  if (props.disabled !== undefined) {
    event.preventDefault();
    return;
  }
  menu?.dismiss();
  emit("select");
}
</script>

<template>
  <RouterLink
    v-if="to !== undefined && disabled === undefined"
    :to="to"
    :class="itemClass"
    role="menuitem"
    tabindex="-1"
    @click="choose"
    ><slot
  /></RouterLink>
  <button
    v-else
    :type="type"
    :class="itemClass"
    role="menuitem"
    tabindex="-1"
    :aria-disabled="disabled === undefined ? undefined : 'true'"
    :aria-describedby="disabled === undefined ? undefined : whyId"
    @click="choose"
  >
    <slot />
    <!-- The item dims; its reason is information and keeps a readable tier (>= 4.5:1). -->
    <span v-if="disabled !== undefined" :id="whyId" class="ml-auto pl-3 text-sm text-text-3">{{
      disabled
    }}</span>
  </button>
</template>
