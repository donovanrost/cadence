<script setup lang="ts">
import {
  DialogContent,
  DialogDescription,
  DialogOverlay,
  DialogPortal,
  DialogRoot,
  DialogTitle,
} from "reka-ui";

/**
 * A modal decision, e.g. "Discard unsaved changes?". The caller owns `open`
 * and supplies the actions; Escape and the scrim dismiss as cancel.
 */
withDefaults(
  defineProps<{
    open: boolean;
    title: string;
    description?: string;
    tone?: "neutral" | "danger";
  }>(),
  { tone: "neutral" },
);
const emit = defineEmits<{ "update:open": [open: boolean] }>();
defineSlots<{ default?(): unknown; actions(): unknown }>();
</script>

<template>
  <DialogRoot :open="open" @update:open="(value) => emit('update:open', value)">
    <DialogPortal>
      <div v-if="open" class="cadence-sheet-layer pointer-events-auto grid place-items-center p-4">
        <DialogOverlay class="cadence-sheet-scrim" />
        <DialogContent
          class="cadence-overlay-panel relative top-auto w-full max-w-md p-5"
          :class="tone === 'danger' ? 'border-error/40' : ''"
        >
          <DialogTitle class="text-base font-semibold">{{ title }}</DialogTitle>
          <DialogDescription v-if="description" class="mt-2 text-sm text-base-content/70">
            {{ description }}
          </DialogDescription>
          <div v-if="$slots.default" class="mt-3 text-sm"><slot /></div>
          <div class="mt-5 flex flex-wrap justify-end gap-2"><slot name="actions" /></div>
        </DialogContent>
      </div>
    </DialogPortal>
  </DialogRoot>
</template>
