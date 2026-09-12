<script setup lang="ts">
import { computed } from "vue";
import LegacyDestination from "../../shared/LegacyDestination.vue";
import { destination, pathIdentity, queryText } from "../../shared/legacy-destination";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ mission_id?: unknown; dashboard_id?: unknown; query?: unknown }>();
const href = computed(() => {
  const query = queryText(props.query, ["version", "selected_publish_issue"]);
  if (!query || !pathIdentity(props.dashboard_id)) return null;
  if (
    query.version &&
    (!/^[1-9][0-9]{0,15}$/.test(query.version) || BigInt(query.version) > 9007199254740990n)
  )
    return null;
  return destination(props.mission_id, `${encodeURIComponent(props.dashboard_id)}/activity`, query);
});
</script>
<template>
  <LegacyDestination id="activity-legacy-redirect" title="Dashboard Activity" :href="href" />
</template>
