<script setup lang="ts">
import { computed } from "vue";
import type { CatalogApplication, HostContext } from "@cadence/plugin-sdk";
import { routeCatalog } from "@cadence/plugin-sdk/routes";
import HostPage from "./shell/HostPage.vue";
import { breadcrumbTrail } from "./shell/breadcrumbs";

/**
 * A federated surface that stands in for a host page gets that page's header,
 * drawn by the host exactly as on the host route; other surfaces render bare.
 */
const props = defineProps<{ application: CatalogApplication; context: HostContext }>();
const route = computed(() => props.application.hostRoute ?? null);
const title = computed(() =>
  route.value
    ? (routeCatalog[route.value].title ?? props.application.surface.navigation.label)
    : "",
);
const breadcrumbs = computed(() => {
  if (!route.value) return [];
  const { missionId, missionName, spacecraftId, spacecraftName } = props.context;
  const path = route.value
    .replace(":mission_id", missionId ?? ":mission_id")
    .replace(":spacecraft_id", spacecraftId ?? ":spacecraft_id");
  return breadcrumbTrail(
    { path: route.value, scope: props.context.scope },
    path,
    { mission: { display_name: missionName }, spacecraft: { display_name: spacecraftName } },
    title.value,
  );
});
</script>

<template>
  <HostPage
    v-if="route"
    :title="title"
    :route="route"
    :breadcrumbs="breadcrumbs"
    :workspace="routeCatalog[route].layer === 'ops'"
    ><slot
  /></HostPage>
  <slot v-else />
</template>
