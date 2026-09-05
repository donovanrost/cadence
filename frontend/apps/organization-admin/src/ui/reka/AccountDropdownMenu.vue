<script setup lang="ts">
import { DropdownMenuContent, DropdownMenuRoot, DropdownMenuTrigger } from "reka-ui";
import { computed, nextTick, onBeforeUnmount, ref, useAttrs } from "vue";

defineOptions({ inheritAttrs: false });

const attrs = useAttrs();
const root = ref<HTMLElement | null>(null);
const open = ref(false);
let suppressCloseAutoFocus = false;

const rootAttrs = computed(() => {
  const { class: _class, ...passthroughAttrs } = attrs;
  return passthroughAttrs;
});

const rootClass = computed(() => [attrs.class, open.value && "dropdown-open"]);

const focusTrigger = async () => {
  await nextTick();
  root.value?.querySelector<HTMLElement>("[data-dropdown-trigger]")?.focus();
};

const focusFirstItem = () => {
  root.value?.querySelector<HTMLElement>("[role='menuitem']")?.focus();
};

const closeWithoutFocus = () => {
  if (!open.value) return;
  suppressCloseAutoFocus = true;
  open.value = false;
};

const updateOpen = (nextOpen: boolean) => {
  open.value = nextOpen;
};

const handleOpenAutoFocus = (event: Event) => {
  event.preventDefault();
  focusFirstItem();
};

const handleCloseAutoFocus = (event: Event) => {
  const restoreFocus = !suppressCloseAutoFocus;
  suppressCloseAutoFocus = false;
  event.preventDefault();
  if (restoreFocus) void focusTrigger();
};

const handleEscapeKeyDown = (event: Event) => {
  event.preventDefault();
  open.value = false;
};

const handleTabKeyDown = () => closeWithoutFocus();
const handleItemSelect = () => closeWithoutFocus();

onBeforeUnmount(() => {
  suppressCloseAutoFocus = true;
  open.value = false;
  root.value?.classList.remove("dropdown-open");
  root.value
    ?.querySelector<HTMLElement>("[data-dropdown-trigger]")
    ?.setAttribute("aria-expanded", "false");
});
</script>

<template>
  <div ref="root" v-bind="rootAttrs" :class="rootClass">
    <DropdownMenuRoot :open="open" :modal="false" @update:open="updateOpen">
      <DropdownMenuTrigger as-child>
        <slot name="trigger" :open="open"></slot>
      </DropdownMenuTrigger>

      <DropdownMenuContent
        v-if="open"
        as-child
        :loop="true"
        @open-auto-focus="handleOpenAutoFocus"
        @close-auto-focus="handleCloseAutoFocus"
        @escape-key-down="handleEscapeKeyDown"
        @keydown.tab="handleTabKeyDown"
      >
        <slot name="content" :open="open" :onItemSelect="handleItemSelect"></slot>
      </DropdownMenuContent>
      <slot v-else name="content" :open="open" :onItemSelect="handleItemSelect"></slot>
    </DropdownMenuRoot>
  </div>
</template>
