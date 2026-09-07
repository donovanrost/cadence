<script setup lang="ts">
import type { PageBreadcrumb } from "./page-chrome";
defineProps<{ items: readonly PageBreadcrumb[] }>();
</script>
<template>
  <nav v-if="items.length" aria-label="Breadcrumb" class="cd-page-breadcrumbs">
    <ol>
      <li v-for="(item, index) in items" :key="item.id ?? `${index}-${item.label}`">
        <span v-if="index" aria-hidden="true" class="cd-page-breadcrumbs__separator">/</span>
        <a v-if="item.href" :id="item.id" :href="item.href">{{ item.label }}</a>
        <span
          v-else
          :id="item.id"
          :aria-current="index === items.length - 1 ? 'page' : undefined"
          >{{ item.label }}</span
        >
      </li>
    </ol>
  </nav>
</template>
