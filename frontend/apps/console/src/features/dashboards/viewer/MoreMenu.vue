<script setup lang="ts" generic="Id extends string">
import { ref, useId } from "vue";
import { useMenuButton } from "@/shell";

/**
 * The dashboards' ⋯ (viewer, directory rows, library, playlists, section headings): a menu button
 * (design-language §6). A disabled item stays focusable and says why (aria-disabled, its reason as
 * description), so 'It's already first.' is reachable by keyboard and read.
 */
withDefaults(
  defineProps<{
    /** `disabled`: why the item can't run now, shown on it (ux: disabled reasons, not silence). */
    items: readonly { id: Id; label: string; disabled?: string | undefined }[];
    label?: string;
  }>(),
  { label: "More dashboard actions" },
);
const emit = defineEmits<{ select: [id: Id] }>();
const root = ref<HTMLElement | null>(null);
const trigger = ref<HTMLButtonElement | null>(null);
const { open, toggle, close, onTriggerKey, onMenuKey } = useMenuButton(root);
const menuId = useId();
const itemClass =
  "flex h-10 w-full cursor-pointer items-center border-0 bg-transparent px-3.5 text-left text-base text-readout hover:bg-raised-hi focus:bg-raised-hi";
/** Back to the trigger first: a sheet the action opens returns focus there when it closes. */
function choose(id: Id) {
  close();
  trigger.value?.focus();
  emit("select", id);
}
</script>

<template>
  <div ref="root" class="relative">
    <button
      ref="trigger"
      type="button"
      class="h-8 w-9 cursor-pointer border border-line bg-raised font-mono text-base text-readout hover:bg-raised-hi max-md:hit-44"
      :aria-label="label"
      :aria-expanded="open"
      aria-haspopup="menu"
      :aria-controls="menuId"
      @click="toggle"
      @keydown="onTriggerKey"
    >
      ⋯
    </button>
    <div
      v-if="open"
      :id="menuId"
      role="menu"
      :aria-label="label"
      class="absolute top-full right-0 z-30 min-w-[200px] border border-line bg-raised py-1.5"
      @keydown="onMenuKey"
    >
      <button
        v-for="item in items"
        :key="item.id"
        type="button"
        role="menuitem"
        tabindex="-1"
        :class="[itemClass, item.disabled ? 'cursor-default text-text-4 hover:bg-transparent' : '']"
        :aria-disabled="item.disabled ? 'true' : undefined"
        :aria-describedby="item.disabled ? `${menuId}-${item.id}-why` : undefined"
        @click="item.disabled || choose(item.id)"
      >
        {{ item.label }}
        <span v-if="item.disabled" :id="`${menuId}-${item.id}-why`" class="ml-auto pl-3 text-sm">{{
          item.disabled
        }}</span>
      </button>
    </div>
  </div>
</template>
