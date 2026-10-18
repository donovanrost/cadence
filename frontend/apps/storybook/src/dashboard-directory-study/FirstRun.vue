<script setup lang="ts">
import CadenceEmptyStateFrame from "@cadence/ui/CadenceEmptyStateFrame.vue";
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import { directoryPath } from "./fixtures";

defineProps<{ author: boolean }>();
</script>

<template>
  <CadenceEmptyStateFrame>
    <template #title>No dashboards yet</template>
    <template #description>
      Dashboards arrange live telemetry for this mission.
      {{
        author
          ? "Start from a blank canvas, or import a dashboard exported from another mission."
          : "Ask a mission author to create the first one."
      }}
    </template>
    <template v-if="author" #action>
      <div class="flex justify-center gap-2">
        <!-- CadenceButton has no link form; these are the button recipes on anchors. -->
        <a :href="`${directoryPath}/new`" class="btn btn-primary btn-sm gap-1"
          ><CadenceIcon name="hero-plus" />New dashboard</a
        >
        <a :href="`${directoryPath}/import`" class="btn btn-sm gap-1"
          ><CadenceIcon name="hero-arrow-down-tray" />Import</a
        >
      </div>
    </template>
  </CadenceEmptyStateFrame>
</template>
