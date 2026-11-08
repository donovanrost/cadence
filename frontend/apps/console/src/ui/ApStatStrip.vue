<script setup lang="ts">
/** Tile grid: 1px hairline gaps form the dividers. Put ApStatTile (or ApFact) children inside. */
withDefaults(defineProps<{ columns?: number; label?: string }>(), { columns: 6 });
</script>

<template>
  <section
    :aria-label="label"
    class="grid gap-px border border-hairline bg-hairline"
    :style="{ gridTemplateColumns: `repeat(${columns}, minmax(0, 1fr))` }"
  >
    <slot />
  </section>
</template>
