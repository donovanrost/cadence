<script setup lang="ts">
import { eventKinds, type EventKind } from "./api.ts";
import { KIND_WORDS } from "./model.ts";

/** Event kind filter (multi): toggles with words, ≥44px targets; selected = white fill (ux #4). */
const props = defineProps<{ selected: readonly EventKind[] }>();
const emit = defineEmits<{ change: [kinds: EventKind[]] }>();
const toggle = (kind: EventKind) =>
  emit(
    "change",
    props.selected.includes(kind)
      ? props.selected.filter((k) => k !== kind)
      : [...props.selected, kind],
  );
</script>

<template>
  <div role="group" aria-label="Event kinds" class="flex flex-wrap gap-1.5">
    <button
      v-for="kind in eventKinds"
      :key="kind"
      type="button"
      class="inline-flex h-11 cursor-pointer items-center border px-3 font-display text-md font-semibold tracking-tag uppercase"
      :class="
        selected.includes(kind)
          ? 'border-readout bg-raised text-readout'
          : 'border-line text-text-3 hover:text-readout'
      "
      :aria-pressed="selected.includes(kind)"
      @click="toggle(kind)"
    >
      {{ KIND_WORDS[kind] }}
    </button>
  </div>
</template>
