<script setup lang="ts">
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import CadenceOpsListFrame from "@cadence/ui/CadenceOpsListFrame.vue";

defineProps<{ label: string; icon: `hero-${string}`; count: number; empty: string }>();
defineSlots<{ default(): unknown; action?(): unknown }>();
</script>

<template>
  <CadenceOpsListFrame :aria-label="label" class="flex flex-col">
    <div class="flex items-center justify-between gap-3 border-b border-base-300 px-4 py-2">
      <h2 class="hud-label flex items-center gap-1.5">
        <CadenceIcon :name="icon" size="xs" />{{ label }}
        <span v-if="count" class="font-mono text-base-content/60">{{ count }}</span>
      </h2>
      <slot name="action" />
    </div>
    <p v-if="count === 0" class="px-4 py-3 text-sm text-base-content/70">{{ empty }}</p>
    <ul v-else class="flex-1 divide-y divide-base-300/60">
      <slot />
    </ul>
  </CadenceOpsListFrame>
</template>
