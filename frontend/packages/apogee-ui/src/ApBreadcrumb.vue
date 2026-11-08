<script setup lang="ts">
import type { RouteLocationRaw } from "vue-router";

export type ApCrumb = Readonly<{ label: string; to?: RouteLocationRaw }>;
/** Last crumb is the current page. */
defineProps<{ crumbs: readonly ApCrumb[] }>();
</script>

<template>
  <nav aria-label="Breadcrumb">
    <ol
      class="m-0 flex list-none flex-wrap items-center gap-2 p-0 font-mono text-sm text-text-4 uppercase"
    >
      <li v-for="(crumb, i) in crumbs" :key="`${i}-${crumb.label}`" class="flex items-center gap-2">
        <span v-if="i > 0" aria-hidden="true">/</span>
        <RouterLink
          v-if="crumb.to && i < crumbs.length - 1"
          :to="crumb.to"
          class="text-text-3 no-underline hover:text-readout"
          >{{ crumb.label }}</RouterLink
        >
        <span
          v-else
          :aria-current="i === crumbs.length - 1 ? 'page' : undefined"
          class="text-readout"
          >{{ crumb.label }}</span
        >
      </li>
    </ol>
  </nav>
</template>
