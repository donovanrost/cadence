<script setup lang="ts">
import type { OpsPageContext, OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import PublicationRequired from "../../shared/publication/PublicationRequired.vue";
import type { PublicationRequirement } from "../../shared/publication/contracts";
import DashboardWorkspace from "./DashboardWorkspace.vue";
import type { WorkspaceSnapshot } from "./contracts";
defineOptions({ inheritAttrs: false });
defineProps<{
  requirement: PublicationRequirement | null;
  model: WorkspaceSnapshot | null;
  context: OpsPageContext;
  port: OpsPagePort;
  refresh: () => Promise<void>;
}>();
</script>
<template>
  <PublicationRequired v-if="requirement" :requirement="requirement" :refresh="refresh" />
  <DashboardWorkspace
    v-else-if="model"
    :model="model"
    :context="context"
    :port="port"
    :refresh="refresh"
  />
</template>
