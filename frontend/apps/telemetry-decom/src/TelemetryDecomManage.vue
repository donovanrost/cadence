<script setup lang="ts">
import { computed, useAttrs, type Component } from "vue";
import SpacecraftTelemetryDecom from "./SpacecraftTelemetryDecom.vue";
import type { TelemetryDecomManageProps } from "./telemetry_decom_props";

defineOptions({ inheritAttrs: false });

const props = defineProps<TelemetryDecomManageProps>();
const attrs = useAttrs();
const spacecraftProps = computed(() => ({ ...props, ...attrs }));
const SpacecraftTelemetryDecomBridge = SpacecraftTelemetryDecom as Component;
</script>

<template>
  <SpacecraftTelemetryDecomBridge v-bind="spacecraftProps" />
</template>
