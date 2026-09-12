<script setup lang="ts">
import { WorkspaceLanding } from "@cadence/plugin-host/ops-workspace";
defineOptions({ inheritAttrs: false });
defineProps<{ model: unknown; organizationId: unknown; missionId: unknown }>();
</script>
<template>
  <WorkspaceLanding :model="model" :organization-id="organizationId" :mission-id="missionId" />
</template>
