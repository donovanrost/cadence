<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import SourceScreen from "./SourceScreen.vue";
import SourcesIndex from "./SourcesIndex.vue";

/** Setup › Data sources (`:sourceId?`): the list, or one source's page (L11). */
const route = useRoute("setup.data-sources");
const sourceId = computed(() =>
  typeof route.params.sourceId === "string" && route.params.sourceId ? route.params.sourceId : null,
);
</script>

<template>
  <SourceScreen v-if="sourceId" :key="sourceId" :source-id="sourceId" />
  <SourcesIndex v-else />
</template>
