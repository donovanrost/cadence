<script setup lang="ts">
import type {BreadcrumbsPresentation} from "./page_shell"

const props = defineProps<{breadcrumbs: BreadcrumbsPresentation}>()
</script>

<template>
  <nav v-bind="props.breadcrumbs.attrs">
    <template v-for="item in props.breadcrumbs.items" :key="item.key">
      <span v-if="item.separator" v-bind="item.separator.attrs">
        {{ item.separator.text }}
      </span>
      <a v-if="item.link" v-bind="item.link.attrs">{{ item.link.text }}</a>
      <span v-if="item.current" v-bind="item.current.attrs">
        {{ item.current.text }}
      </span>
    </template>
  </nav>
</template>
