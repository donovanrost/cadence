<script setup lang="ts">
/** One fact tile for an ApStatStrip used as a fact strip: label + mono value. */
defineProps<{ label: string; value?: string | undefined; next?: boolean }>();
</script>

<template>
  <div
    class="flex flex-col gap-1.5 bg-panel px-4 py-3"
    :class="next ? 'shadow-[inset_0_2px_0_var(--color-readout)]' : ''"
  >
    <span class="ap-label">{{ label }}</span>
    <span class="font-mono text-base font-medium" :class="next ? 'text-readout' : 'text-text-2'">
      <slot>{{ value ?? "—" }}</slot>
    </span>
  </div>
</template>
