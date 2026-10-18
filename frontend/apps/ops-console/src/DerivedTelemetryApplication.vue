<script setup lang="ts">
import type { FullPageSurfaceProps } from "@cadence/plugin-sdk";
import {
  definitionsContribution,
  type DefinitionsPort,
} from "@cadence/derived-telemetry/definitions";

import { useMissionContribution } from "./mission-contribution";
const props = defineProps<FullPageSurfaceProps>();
const { document, loading, error, session, load } = useMissionContribution<
  Parameters<DefinitionsPort["save"]>[0]
>(
  props,
  [{ ...definitionsContribution, saveAction: definitionsContribution.actionId }],
  "Current derived telemetry evidence could not be loaded.",
);
</script>
<template>
  <section v-if="loading" id="derived-loading" role="status" class="p-5 text-sm">
    Loading derived telemetry…
  </section>
  <section
    v-else-if="error"
    id="derived-load-error"
    role="alert"
    class="space-y-3 border border-warning/40 p-5"
  >
    <p>{{ error }}</p>
    <button id="retry-derived-load" class="btn btn-sm" @click="load">Retry</button>
  </section>
  <component
    :is="session.component"
    v-else-if="session"
    :key="session.key"
    :document="document"
    :host-context="session.context"
    :port="session.port"
  />
</template>
