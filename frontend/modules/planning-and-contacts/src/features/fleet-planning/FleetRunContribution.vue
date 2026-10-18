<script setup lang="ts">
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import type { FleetRunModel, FleetRunPort } from "./OpsFleetPlanningRun.contracts";
import OpsFleetPlanningRun from "./OpsFleetPlanningRun.vue";
import { useFleetBootstrap } from "./use-fleet-bootstrap";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ run: FleetRunModel; port: OpsPagePort; readPort: OpsPageReadPort }>();
const run = useFleetBootstrap(() => props.run);
const actions = { continue: "refresh-fleet-run", repair: "repair-fleet-run" } as const;
const port: FleetRunPort = {
  context: { ...props.run.context },
  refresh: () => props.readPort.read(),
  execute(action, input) {
    if (!Object.hasOwn(actions, action)) throw Error("Undeclared fleet run action.");
    return props.port.execute(actions[action], input);
  },
};
</script>
<template><OpsFleetPlanningRun :run="run" :port="port" /></template>
