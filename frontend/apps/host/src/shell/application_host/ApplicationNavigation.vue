<script setup lang="ts">
import type { Navigation } from "./presentation_types";

defineProps<{ navigation: Navigation }>();
</script>

<template>
  <nav
    :id="navigation.id"
    :aria-label="navigation.label"
    class="mb-5 flex flex-wrap items-center gap-1 border-b border-base-300/70"
  >
    <a
      v-for="item in navigation.items"
      :id="item.id"
      :key="item.surface_id"
      :href="item.href"
      data-phx-link="redirect"
      data-phx-link-state="push"
      :aria-current="item.current ? 'page' : undefined"
      class="relative -mb-px border-b-2 px-3 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition-colors"
      :class="
        item.current
          ? 'border-primary text-primary'
          : 'border-transparent text-base-content/55 hover:border-base-content/30 hover:text-base-content'
      "
      >{{ item.label }}</a
    >
  </nav>
</template>
