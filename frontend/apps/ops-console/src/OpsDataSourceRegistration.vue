<script setup lang="ts">
import {
  OpsDataSources,
  type DataSourcesPresentation,
} from "@cadence/data-operations/data-sources";

defineOptions({ inheritAttrs: false });
const props = defineProps<{ page: DataSourcesPresentation }>();
</script>

<template>
  <OpsDataSources :page="props.page" v-bind="$attrs" />
</template>
