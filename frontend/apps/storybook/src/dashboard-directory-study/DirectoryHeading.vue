<script setup lang="ts">
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import NewDashboardMenu from "./NewDashboardMenu.vue";
import { missionPath } from "./fixtures";

defineProps<{ author: boolean }>();
</script>

<template>
  <CadencePageHeading>
    <template #title>Dashboards</template>
    <template #description>
      Telemetry workspaces shared across the mission. Stars and recently viewed are yours alone.
    </template>
    <template #actions>
      <!-- CadenceButton has no link form; navigation stays an anchor in the quiet recipe. -->
      <a :href="`${missionPath}/ops/library`" class="btn btn-ghost btn-sm gap-1">
        <CadenceIcon name="hero-rectangle-stack" />Library
      </a>
      <a :href="`${missionPath}/ops/playlists`" class="btn btn-ghost btn-sm gap-1">
        <CadenceIcon name="hero-play" />Playlists
      </a>
      <NewDashboardMenu v-if="author" />
    </template>
  </CadencePageHeading>
</template>
