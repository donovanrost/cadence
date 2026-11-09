<script setup lang="ts">
import type { RouteLocationRaw } from "vue-router";

/** Section navigation between routes (links, not ARIA tabs). Looks like ApSegmented `tabs`. */
export type ApTabLink = Readonly<{
  key: string;
  label: string;
  to: RouteLocationRaw;
  count?: number;
}>;
defineProps<{ links: readonly ApTabLink[]; active: string; label: string }>();
</script>

<template>
  <nav :aria-label="label" class="flex border-b border-hairline">
    <RouterLink
      v-for="link in links"
      :key="link.key"
      :to="link.to"
      :aria-current="link.key === active ? 'page' : undefined"
      class="flex h-9 items-center gap-2 max-md:hit-44 border-r border-hairline px-4 font-display text-md font-semibold tracking-tag uppercase no-underline last:border-r-0"
      :class="
        link.key === active
          ? 'bg-raised text-readout shadow-[inset_0_-2px_0_var(--color-readout)]'
          : 'text-text-3 hover:text-readout'
      "
    >
      {{ link.label
      }}<span v-if="link.count !== undefined" class="font-mono text-xs">{{ link.count }}</span>
    </RouterLink>
  </nav>
</template>
