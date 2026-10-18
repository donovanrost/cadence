<script setup lang="ts">
import { ref } from "vue";
import { DialogContent, DialogOverlay, DialogPortal, DialogRoot, DialogTitle } from "reka-ui";
import CadenceIconButton from "./CadenceIconButton.vue";

withDefaults(defineProps<{ open: boolean; title: string; width?: "sm" | "md" | "lg" }>(), {
  width: "md",
});
const emit = defineEmits<{ "update:open": [open: boolean] }>();
const heading = ref<HTMLHeadingElement>();

function focusHeading(event: Event) {
  event.preventDefault();
  heading.value?.focus();
}
</script>

<template>
  <DialogRoot :open="open" @update:open="emit('update:open', $event)">
    <DialogPortal>
      <div v-if="open" class="cadence-sheet-layer">
        <DialogOverlay class="cadence-sheet-scrim" />
        <DialogContent
          class="cadence-sheet"
          :data-sheet-width="width"
          aria-modal="true"
          :aria-describedby="undefined"
          @open-auto-focus="focusHeading"
        >
          <header class="cadence-sheet-header">
            <DialogTitle as-child>
              <h2 ref="heading" class="hud-label" tabindex="-1">{{ title }}</h2>
            </DialogTitle>
            <CadenceIconButton
              icon="hero-x-mark"
              label="Close"
              @click="emit('update:open', false)"
            />
          </header>
          <div class="cadence-sheet-body"><slot /></div>
        </DialogContent>
      </div>
    </DialogPortal>
  </DialogRoot>
</template>
