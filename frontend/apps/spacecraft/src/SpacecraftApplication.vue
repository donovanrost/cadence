<script setup lang="ts">
import { computed, useAttrs, type Component } from "vue";
import SpacecraftApplications from "./SpacecraftApplications.vue";
import SpacecraftApplicationsPage from "./SpacecraftApplicationsPage.vue";
import SpacecraftCommanding from "./SpacecraftCommanding.vue";
import SpacecraftEdit from "./SpacecraftEdit.vue";
import SpacecraftList from "./SpacecraftList.vue";
import SpacecraftListPage from "./SpacecraftListPage.vue";
import SpacecraftNew from "./SpacecraftNew.vue";
import SpacecraftReadiness from "./SpacecraftReadiness.vue";
import SpacecraftRouting from "./SpacecraftRouting.vue";
import SpacecraftShow from "./SpacecraftShow.vue";
import SpacecraftTelemetryDecom from "./SpacecraftTelemetryDecom.vue";
import SpacecraftTypeList from "./SpacecraftTypeList.vue";
import SpacecraftTypeListPage from "./SpacecraftTypeListPage.vue";
import SpacecraftTypeNew from "./SpacecraftTypeNew.vue";
import SpacecraftTypeShow from "./SpacecraftTypeShow.vue";

type SpacecraftComponentName =
  | "SpacecraftApplications"
  | "SpacecraftApplicationsPage"
  | "SpacecraftCommanding"
  | "SpacecraftEdit"
  | "SpacecraftList"
  | "SpacecraftListPage"
  | "SpacecraftNew"
  | "SpacecraftReadiness"
  | "SpacecraftRouting"
  | "SpacecraftShow"
  | "SpacecraftTelemetryDecom"
  | "SpacecraftTypeList"
  | "SpacecraftTypeListPage"
  | "SpacecraftTypeNew"
  | "SpacecraftTypeShow";

defineOptions({ inheritAttrs: false });

const props = defineProps<{
  component?: SpacecraftComponentName;
  pageProps?: Record<string, unknown>;
}>();

const attrs = useAttrs();

const components: Record<SpacecraftComponentName, Component> = {
  SpacecraftApplications,
  SpacecraftApplicationsPage,
  SpacecraftCommanding,
  SpacecraftEdit,
  SpacecraftList,
  SpacecraftListPage,
  SpacecraftNew,
  SpacecraftReadiness,
  SpacecraftRouting,
  SpacecraftShow,
  SpacecraftTelemetryDecom,
  SpacecraftTypeList,
  SpacecraftTypeListPage,
  SpacecraftTypeNew,
  SpacecraftTypeShow,
};

const selectedComponent = computed(() => components[props.component ?? "SpacecraftListPage"]);
</script>

<template>
  <div id="spacecraft-remote-application" class="contents">
    <component :is="selectedComponent" v-bind="{ ...(props.pageProps ?? {}), ...attrs }" />
  </div>
</template>
