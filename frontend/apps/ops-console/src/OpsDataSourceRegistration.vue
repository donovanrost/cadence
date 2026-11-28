<script setup lang="ts">
import DataSourcesWorkspaceLink from "./DataSourcesWorkspaceLink.vue";
import type { DataSourcesPresentation } from "./data-sources-presentation";

defineOptions({ inheritAttrs: false });
const props = defineProps<{ page: DataSourcesPresentation }>();
</script>

<template>
  <DataSourcesWorkspaceLink :page="props.page" v-bind="$attrs" />
</template>
