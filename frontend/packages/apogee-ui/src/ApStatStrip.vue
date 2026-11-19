<script setup lang="ts">
import { computed } from "vue";
import { stripColumns } from "./stat-strip.ts";

/**
 * Tile grid: 1px hairline gaps form the dividers. Put ApStatTile (or ApFact) children inside and
 * set `columns` to the number of tiles. Columns: up to 2 under 768px, up to 3 from 768 to 1100px,
 * all tiles in one row above, choosing counts that divide the tiles evenly where possible.
 */
const props = withDefaults(
  defineProps<{ columns?: number | undefined; label?: string | undefined }>(),
  { columns: 6 },
);
const cols = computed(() => stripColumns(props.columns));
</script>

<template>
  <section
    :aria-label="label"
    class="grid grid-cols-[repeat(var(--ap-cols-sm),minmax(0,1fr))] gap-px border border-hairline bg-hairline md:grid-cols-[repeat(var(--ap-cols-md),minmax(0,1fr))] console:grid-cols-[repeat(var(--ap-cols),minmax(0,1fr))]"
    :style="{ '--ap-cols-sm': cols.small, '--ap-cols-md': cols.medium, '--ap-cols': cols.wide }"
  >
    <slot />
  </section>
</template>
