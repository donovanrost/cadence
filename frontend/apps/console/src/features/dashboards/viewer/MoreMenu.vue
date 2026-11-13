<script setup lang="ts" generic="Id extends string">
import { ref, useId } from "vue";
import { useDisclosure } from "@/shell";

/** The viewer's ⋯ menu (ux): a disclosure of actions, in AccountMenu's pattern. */
defineProps<{ items: readonly { id: Id; label: string }[] }>();
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
      aria-label="More dashboard actions"
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
        :class="itemClass"
        @click="choose(item.id)"
      >
        {{ item.label }}
      </button>
    </div>
  </div>
</template>
