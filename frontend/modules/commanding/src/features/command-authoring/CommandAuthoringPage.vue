<script setup lang="ts">
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import AuthoringPrerequisite from "./AuthoringPrerequisite.vue";
import CommandAuthoring from "./CommandAuthoring.vue";
import type { AuthoringPage, AuthoringPrerequisite as Prerequisite } from "./contracts";

defineOptions({ inheritAttrs: false });
defineProps<{
  page: AuthoringPage | Prerequisite;
  port: OpsPagePort;
  readPort: OpsPageReadPort;
  refresh: () => Promise<void>;
}>();
</script>
<template>
  <CommandAuthoring v-if="'catalog' in page" :page="page" :port="port" :read-port="readPort" />
  <AuthoringPrerequisite v-else :mission-id="page.context.missionId" :refresh="refresh" />
</template>
