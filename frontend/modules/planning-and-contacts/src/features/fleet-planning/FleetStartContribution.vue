<script setup lang="ts">
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import type { FleetStartModel, FleetStartPort } from "./OpsFleetPlanningNew.contracts";
import OpsFleetPlanningNew from "./OpsFleetPlanningNew.vue";
import { useFleetBootstrap } from "./use-fleet-bootstrap";
defineOptions({ inheritAttrs: false });
const props = defineProps<{
  start: FleetStartModel;
  port: OpsPagePort;
  readPort: OpsPageReadPort;
}>();
const start = useFleetBootstrap(() => props.start);
const actions = { preview: "validate-fleet-run", create: "create-fleet-run" } as const;
const port: FleetStartPort = {
  context: { ...props.start.context },
  refresh: () => props.readPort.read(),
  execute(action, input) {
    if (!Object.hasOwn(actions, action)) throw Error("Undeclared fleet start action.");
    return props.port.execute(actions[action], input);
  },
};
</script>
<template><OpsFleetPlanningNew :start="start" :port="port" /></template>
