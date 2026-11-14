<script setup lang="ts" generic="Id extends string">
import { ref, useId } from "vue";
import { useDisclosure } from "@/shell";

/** The viewer's ⋯ menu (ux): a disclosure of actions, in AccountMenu's pattern. */
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
const { open, toggle, close } = useDisclosure(root);
const menuId = useId();
const itemClass =
  "flex h-10 w-full cursor-pointer items-center border-0 bg-transparent px-3.5 text-left text-base text-readout hover:bg-raised-hi";
function choose(id: Id) {
  close();
  emit("select", id);
}
</script>

<template>
  <div ref="root" class="relative">
    <button
      type="button"
      class="h-8 w-9 cursor-pointer border border-line bg-raised font-mono text-base text-readout hover:bg-raised-hi max-md:hit-44"
      :aria-label="label"
      :aria-expanded="open"
      aria-haspopup="true"
      :aria-controls="menuId"
      @click="toggle"
    >
      ⋯
    </button>
    <div
      v-if="open"
      :id="menuId"
      class="absolute top-full right-0 z-30 min-w-[200px] border border-line bg-raised py-1.5"
    >
      <button
        v-for="item in items"
        :key="item.id"
        type="button"
        :class="[itemClass, item.disabled ? 'cursor-default text-text-4 hover:bg-transparent' : '']"
        :aria-disabled="item.disabled ? 'true' : undefined"
        @click="item.disabled || choose(item.id)"
      >
        {{ item.label }}
        <span v-if="item.disabled" class="ml-auto pl-3 text-sm">{{ item.disabled }}</span>
      </button>
    </div>
  </div>
</template>
