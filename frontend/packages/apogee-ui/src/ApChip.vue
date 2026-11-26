<script setup lang="ts">
import { onBeforeUnmount, onUnmounted, ref } from "vue";
import { chipFocusCandidates, refocusFirst } from "./lib/focus.ts";

/**
 * Mono chip. `name` renders a key in text-4 before the value; `removable` adds a labelled × button.
 * When the chip leaves while its × has focus, focus moves to the next chip's ×, else the previous
 * one's, else the group's field (a11y A5), however late the caller removes it.
 */
defineProps<{ name?: string | undefined; removable?: boolean | undefined; removeLabel?: string }>();
defineEmits<{ remove: [] }>();

const button = ref<HTMLButtonElement | null>(null);
let handoff: readonly (HTMLElement | null)[] = [];
onBeforeUnmount(() => {
  const el = button.value;
  handoff = el && document.activeElement === el ? chipFocusCandidates(el) : [];
});
onUnmounted(() => {
  if (handoff.length > 0) refocusFirst(...handoff);
  handoff = [];
});
</script>

<template>
  <span
    data-ap-chip
    class="inline-flex h-7 items-center gap-1.5 border border-line bg-raised pl-2.5 font-mono text-sm text-readout"
    :class="removable ? 'pr-0.5' : 'pr-2.5'"
  >
    <span v-if="name" class="text-text-4">{{ name }}</span>
    <slot />
    <button
      v-if="removable"
      ref="button"
      type="button"
      data-ap-chip-remove
      class="inline-flex size-[22px] cursor-pointer max-md:hit-44 items-center justify-center border-0 bg-transparent text-text-3 hover:text-readout"
      :aria-label="removeLabel ?? 'Remove'"
      @click="$emit('remove')"
    >
      ×
    </button>
  </span>
</template>
