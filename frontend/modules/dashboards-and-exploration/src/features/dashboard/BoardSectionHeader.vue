<script setup lang="ts">
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import CadenceIconButton from "@cadence/ui/CadenceIconButton.vue";
import type { WorkspaceSnapshot } from "../workspace/contracts";

defineProps<{
  section: WorkspaceSnapshot["sections"][number];
  count: number;
  open: boolean;
  editing: boolean;
  first: boolean;
  last: boolean;
}>();
const emit = defineEmits<{ toggle: []; edit: []; move: [direction: "up" | "down"]; remove: [] }>();
</script>

<template>
  <header class="flex items-center gap-2 border-b border-base-300/60 py-1.5">
    <button
      type="button"
      class="flex min-w-0 flex-1 items-center gap-2 text-left"
      :aria-expanded="open"
      @click="emit('toggle')"
    >
      <span class="transition-transform" :class="open ? 'rotate-90' : ''">
        <CadenceIcon name="hero-chevron-right" />
      </span>
      <h2 class="hud-label truncate">{{ section.title }}</h2>
      <span class="shrink-0 font-mono text-xs text-base-content/60">{{ count }}</span>
      <span v-if="section.description" class="truncate text-xs text-base-content/60">
        {{ section.description }}
      </span>
    </button>
    <div
      v-if="editing"
      class="flex shrink-0 items-center"
      role="group"
      :aria-label="`${section.title} section`"
    >
      <CadenceIconButton
        icon="hero-arrow-up"
        label="Move section up"
        :disabled="first"
        @click="emit('move', 'up')"
      />
      <CadenceIconButton
        icon="hero-arrow-down"
        label="Move section down"
        :disabled="last"
        @click="emit('move', 'down')"
      />
      <CadenceIconButton icon="hero-pencil-square" label="Edit section" @click="emit('edit')" />
      <CadenceIconButton
        icon="hero-trash"
        label="Remove section"
        tone="danger"
        @click="emit('remove')"
      />
    </div>
  </header>
</template>
