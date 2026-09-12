<script setup lang="ts">
import type { OpsPageContext, OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import PublicationRequired from "../../shared/publication/PublicationRequired.vue";
import type { PublicationRequirement } from "../../shared/publication/contracts";
import ExecutionDiagnosticsPage from "./ExecutionDiagnosticsPage.vue";

defineOptions({ inheritAttrs: false });
defineProps<{
  requirement: PublicationRequirement | null;
  state: unknown;
  context: OpsPageContext;
  port: OpsPagePort;
  refresh: () => Promise<void>;
}>();
</script>
<template>
  <PublicationRequired v-if="requirement" :requirement="requirement" :refresh="refresh" />
  <ExecutionDiagnosticsPage
    v-else-if="state"
    :state="state"
    :context="context"
    :port="port"
    :refresh="refresh"
  />
</template>
