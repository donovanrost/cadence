<script setup lang="ts">
import { useMissionScope } from "@/shell";
import StagedBarView from "./StagedBarView.vue";

/** Keyed by mission so switching missions starts a fresh shared query. */
const scope = useMissionScope();
</script>

<template>
  <StagedBarView :key="scope.mission.id" :mission-id="scope.mission.id" />
</template>
