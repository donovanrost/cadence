<script setup lang="ts">
import type { FullPageSurfaceProps } from "@cadence/plugin-sdk";
import {
  definitionsContribution,
  type DefinitionsPort,
} from "@cadence/limits-and-alarming/definitions";
import { postureContribution } from "@cadence/limits-and-alarming/posture";
import { useMissionContribution } from "./mission-contribution";
const props = defineProps<FullPageSurfaceProps>();
const { document, loading, error, session, load } = useMissionContribution<
  Parameters<DefinitionsPort["save"]>[0]
>(
  props,
  [{ ...definitionsContribution, saveAction: "save_limit_definition" }, postureContribution],
  "Limit evidence could not be loaded.",
);
</script>
<template>
  <section v-if="loading" id="limits-loading" role="status" class="p-5 text-sm">
    Loading limit evidence…
  </section>
  <section
    v-else-if="error"
    id="limits-load-error"
    role="alert"
    class="space-y-3 border border-warning/40 p-5"
  >
    <p>{{ error }}</p>
    <button id="retry-limits-load" class="btn btn-sm" @click="load">Retry</button>
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
