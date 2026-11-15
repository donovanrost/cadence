<script setup lang="ts">
// The remote's entry: the console federation smoke's surfaces get SmokeContracts; the development
// demo host (no surface prop, or runtime_contracts) keeps the original probe view.
import type { FederatedApplicationProps, FullPageSurfaceProps } from "@cadence/plugin-sdk";
import { computed } from "vue";
import ContractProbeApplication from "./ContractProbeApplication.vue";
import SmokeContracts from "./SmokeContracts.vue";

const props = defineProps<FederatedApplicationProps & Partial<FullPageSurfaceProps>>();
const smokeSurfaces = new Set(["mission_contracts", "spacecraft_contracts"]);
const smoke = computed(() =>
  props.surface && smokeSurfaces.has(props.surface.surfaceId)
    ? (props as FullPageSurfaceProps)
    : undefined,
);
</script>

<template>
  <SmokeContracts v-if="smoke" v-bind="smoke" />
  <ContractProbeApplication v-else :context="props.context" :bridge="props.bridge" />
</template>
