<script setup lang="ts">
/**
 * A section's heading in the viewer (ux Dashboards.md › Grid › 'Sections in the viewer'): a
 * disclosure (▾ open, ▸ collapsed; Enter/Space), the widget count as meta while collapsed, and the
 * description under the title (text-3, two lines).
 */
defineProps<{
  title: string;
  description: string | null;
  count: number;
  open: boolean;
  bodyId: string;
}>();
const emit = defineEmits<{ toggle: [] }>();
</script>

<template>
  <header class="flex flex-col gap-1">
    <h2 class="m-0">
      <button
        type="button"
        class="flex w-full cursor-pointer items-center gap-2 border-0 bg-transparent p-0 text-left font-display text-sm uppercase tracking-title text-text-2"
        :aria-expanded="open"
        :aria-controls="bodyId"
        @click="emit('toggle')"
      >
        <span aria-hidden="true" class="w-3 text-text-4">{{ open ? "▾" : "▸" }}</span>
        {{ title }}
        <span v-if="!open" class="ml-auto font-mono text-xs text-text-4">
          {{ count }} {{ count === 1 ? "WIDGET" : "WIDGETS" }}
        </span>
      </button>
    </h2>
    <p v-if="description && open" class="m-0 line-clamp-2 pl-5 text-sm text-text-3">
      {{ description }}
    </p>
  </header>
</template>
