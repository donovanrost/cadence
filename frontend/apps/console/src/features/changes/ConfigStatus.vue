<script setup lang="ts">
import { useMissionScope } from "@/shell";
import ConfigStatusView from "./ConfigStatusView.vue";

/** Keyed by mission so switching missions starts a fresh shared query. */
const scope = useMissionScope();
</script>

<template>
  <ConfigStatusView :key="scope.mission.id" :mission-id="scope.mission.id" />
</template>
