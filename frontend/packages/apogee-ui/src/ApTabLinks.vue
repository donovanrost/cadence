<script setup lang="ts">
import { nextTick, onMounted, ref, watch } from "vue";
import type { RouteLocationRaw } from "vue-router";

/** Section navigation between routes (links, not ARIA tabs). Looks like ApSegmented `tabs`. */
export type ApTabLink = Readonly<{
  key: string;
  label: string;
  to: RouteLocationRaw;
  count?: number;
}>;
const props = defineProps<{ links: readonly ApTabLink[]; active: string; label: string }>();
/** On a narrow screen the strip scrolls sideways; the active link is kept in view (ux U94). */
const nav = ref<HTMLElement | null>(null);
function showActive() {
  void nextTick(() =>
    nav.value
      ?.querySelector<HTMLElement>('[aria-current="page"]')
      ?.scrollIntoView?.({ block: "nearest", inline: "nearest" }),
  );
}
onMounted(showActive);
watch(() => props.active, showActive);
</script>

<template>
  <nav ref="nav" :aria-label="label" class="flex overflow-x-auto border-b border-hairline">
    <RouterLink
      v-for="link in links"
      :key="link.key"
      :to="link.to"
      :aria-current="link.key === active ? 'page' : undefined"
      class="flex h-9 flex-none items-center gap-2 whitespace-nowrap max-md:hit-44 border-r border-hairline px-4 font-display text-md font-semibold tracking-tag uppercase no-underline last:border-r-0"
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
