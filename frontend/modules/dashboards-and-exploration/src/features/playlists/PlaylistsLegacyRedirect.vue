<script setup lang="ts">
import { computed } from "vue";
import LegacyDestination from "../../shared/LegacyDestination.vue";
import { destination, queryText } from "../../shared/legacy-destination";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ mission_id?: unknown; query?: unknown }>();
const href = computed(() => {
  const query = queryText(props.query, []);
  return query ? destination(props.mission_id, "playlists", query) : null;
});
</script>
<template>
  <LegacyDestination id="playlists-legacy-redirect" title="Dashboard Playlists" :href="href" />
</template>
