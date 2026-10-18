<script setup lang="ts">
import { shallowRef, watch } from "vue";
import type { OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import type { FleetDirectory, FleetDirectoryPort } from "./OpsFleetPlanning.contracts";
import OpsFleetPlanning from "./OpsFleetPlanning.vue";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ directory: FleetDirectory; readPort: OpsPageReadPort }>();
// Host envelope/context updates may re-admit unchanged bootstrap data. They must
// not invalidate an in-flight feature read or overwrite its newer evidence.
const directory = shallowRef(props.directory);
const signature = (value: FleetDirectory) =>
  JSON.stringify(value, (_key, item) =>
    item && typeof item === "object" && !Array.isArray(item)
      ? Object.fromEntries(
          Object.keys(item)
            .sort()
            .map((key) => [key, item[key]]),
        )
      : item,
  );
watch(
  () => props.directory,
  (next) => {
    if (signature(next) !== signature(directory.value)) directory.value = next;
  },
);
const port: FleetDirectoryPort = {
  context: { ...props.directory.context },
  refresh: () => props.readPort.read(),
};
</script>
<template>
  <OpsFleetPlanning :directory="directory" :port="port" />
</template>
