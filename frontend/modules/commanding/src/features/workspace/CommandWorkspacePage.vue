<script setup lang="ts">
import { useOpsHeader } from "@cadence/plugin-sdk/page-header";
import type {
  OpsPagePort,
  OpsPageContext,
  LiveOpsPageReadPort,
} from "@cadence/plugin-sdk/ops-pages";
import { CommandMonitor } from "@cadence/commanding/mission-commands";
import CommandWorkspace from "./CommandWorkspace.vue";
import type { WorkspacePage } from "./contracts";
import { computed, shallowRef } from "vue";
import { readWorkspace } from "./contracts";
import { useLiveWorkspaceRead } from "./useLiveWorkspaceRead";
const props = defineProps<{
  page: WorkspacePage;
  context: OpsPageContext;
  port: OpsPagePort;
  readPort: LiveOpsPageReadPort;
  refresh: () => Promise<void>;
}>();
const page = shallowRef(props.page);
const { refresh: refreshObservation, syncFailed } = useLiveWorkspaceRead(
  props.readPort,
  computed(() => page.value.state !== "observe"),
  (value) => {
    page.value = readWorkspace(value, props.context);
  },
);
useOpsHeader("/missions/:mission_id/ops/commands/workspace", {
  description: "Choose targets, prepare commands and follow them through review and release.",
});
</script>
<template>
  <CommandWorkspace
    v-if="page.state === 'prepare'"
    :page="page"
    :port="port"
    :read-port="readPort"
    @observe="page = $event"
  />
  <template v-else>
    <CommandMonitor
      live
      :sync-failed="syncFailed"
      :model="page.monitor"
      :context="context"
      :port="port"
      :refresh="refreshObservation"
    />
  </template>
</template>
