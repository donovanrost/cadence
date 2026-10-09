<script setup lang="ts">
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceEmptyStateFrame from "@cadence/ui/CadenceEmptyStateFrame.vue";
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import { dashboardsPath } from "./href";

defineProps<{ mission: string; author: boolean }>();
const emit = defineEmits<{ archived: [] }>();
</script>

<template>
  <CadenceEmptyStateFrame id="dashboard-directory-first-run">
    <template #title>No dashboards yet</template>
    <template #description>
      Dashboards arrange live telemetry for this mission.
      {{
        author
          ? "Start from a blank canvas, or import a dashboard exported from another mission."
          : "Ask a mission author to create the first one."
      }}
    </template>
    <template #action>
      <div class="flex flex-wrap justify-center gap-2">
        <!-- CadenceButton has no link form; these are the button recipes on anchors. -->
        <template v-if="author">
          <a :href="`${dashboardsPath(mission)}/new`" class="btn btn-primary btn-sm gap-1">
            <CadenceIcon name="hero-plus" />New dashboard
          </a>
          <a :href="`${dashboardsPath(mission)}/new?mode=import`" class="btn btn-sm gap-1">
            <CadenceIcon name="hero-arrow-down-tray" />Import
          </a>
        </template>
        <CadenceButton size="sm" variant="quiet" @click="emit('archived')"
          >Show archived</CadenceButton
        >
      </div>
    </template>
  </CadenceEmptyStateFrame>
</template>
