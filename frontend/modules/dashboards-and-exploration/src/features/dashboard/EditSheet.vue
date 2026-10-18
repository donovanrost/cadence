<script setup lang="ts">
import CadenceIconButton from "@cadence/ui/CadenceIconButton.vue";

defineProps<{ title: string; width?: "sm" | "md" | "lg" }>();
const emit = defineEmits<{ close: [] }>();
</script>

<template>
  <div class="cadence-sheet-layer" @keydown.esc="emit('close')">
    <div class="cadence-sheet-scrim" aria-hidden="true" @click="emit('close')"></div>
    <aside
      class="cadence-sheet"
      :data-sheet-width="width ?? 'md'"
      role="dialog"
      aria-modal="true"
      :aria-label="title"
    >
      <header class="cadence-sheet-header">
        <h2 class="hud-label">{{ title }}</h2>
        <CadenceIconButton icon="hero-x-mark" label="Close" @click="emit('close')" />
      </header>
      <div class="cadence-sheet-body">
        <slot />
      </div>
    </aside>
  </div>
</template>
