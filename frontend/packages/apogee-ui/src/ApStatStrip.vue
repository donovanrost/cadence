<script setup lang="ts">
/**
 * Tile grid: 1px hairline gaps form the dividers. Put ApStatTile (or ApFact) children inside.
 * Columns: 2 under 768px, 3 from 768 to 1100px, `columns` above.
 */
withDefaults(defineProps<{ columns?: number | undefined; label?: string | undefined }>(), {
  columns: 6,
});
</script>

<template>
  <section
    :aria-label="label"
    class="grid grid-cols-2 gap-px border border-hairline bg-hairline md:grid-cols-3 console:grid-cols-[repeat(var(--ap-cols),minmax(0,1fr))]"
    :style="{ '--ap-cols': columns }"
  >
    <slot />
  </section>
</template>
