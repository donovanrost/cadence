<script setup lang="ts">
import { computed } from "vue";
import LegacyDestination from "../../shared/LegacyDestination.vue";
import { destination, pathIdentity, queryText } from "../../shared/legacy-destination";
defineOptions({ inheritAttrs: false });
const props = defineProps<{
  mission_id?: unknown;
  dashboard_id?: unknown;
  mode?: unknown;
  query?: unknown;
}>();
// Retain declared legacy selectors verbatim. The canonical page admits their
// runtime meaning, including unavailable states for unsupported selections.
const viewerKeys = [
  "panel",
  "activity_filter",
  "activity_event",
  "selected_publish_issue",
  "selected_time",
  "time_mode",
  "time_axis",
  "from",
  "to",
  "limit_mode",
  "replay_run_id",
  "selection_view",
  "selected_widget",
  "selected_target",
  "selected_id",
  "selected_placement",
  "selected_data_view",
  "selected_scope_kind",
  "selected_scope_id",
  "selected_resource_id",
  "selected_spacecraft_id",
  "selected_contact_id",
  "selected_transport_id",
  "selected_source_endpoint_id",
  "selected_ground_station_id",
  "selected_scope_link_id",
  "realm",
  "data_source_id",
  "source_binding_id",
] as const;
const href = computed(() => {
  if (!pathIdentity(props.dashboard_id) || (props.mode !== "view" && props.mode !== "edit"))
    return null;
  const query = queryText(props.query, props.mode === "view" ? viewerKeys : []);
  if (!query) return null;
  return destination(
    props.mission_id,
    encodeURIComponent(props.dashboard_id) + (props.mode === "edit" ? "/edit" : ""),
    query,
  );
});
</script>
<template>
  <LegacyDestination
    id="workspace-legacy-redirect"
    :title="mode === 'edit' ? 'Edit Dashboard' : 'Dashboard'"
    :href="href"
  />
</template>
