<script setup lang="ts">
import { computed } from "vue";
import LegacyDestination from "../../shared/LegacyDestination.vue";
import { destination, pathIdentity, queryText } from "../../shared/legacy-destination";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ mission_id?: unknown; playlist_id?: unknown; query?: unknown }>();
const href = computed(() => {
  const query = queryText(props.query, ["index"]);
  if (!query || !pathIdentity(props.playlist_id)) return null;
  if (query.index && !/^(0|[1-9][0-9]?)$/.test(query.index)) return null;
  return destination(
    props.mission_id,
    `playlists/${encodeURIComponent(props.playlist_id)}/present`,
    query,
  );
});
</script>
<template>
  <LegacyDestination
    id="playlist-presentation-legacy-redirect"
    title="Present Playlist"
    :href="href"
  />
</template>
