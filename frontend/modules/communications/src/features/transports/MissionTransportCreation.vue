<script setup lang="ts">
import type { MissionPagePort } from "@cadence/plugin-sdk/mission-pages";
import type { ReadContext } from "../../shared/read-contracts";
import { missionFormPort, type SetupPhase } from "../../shared/mission-form-port";
import SetupOutcome from "../../shared/SetupOutcome.vue";
import { readForm } from "./form-validation";
import TransportCreation from "./TransportCreation.vue";
const props = defineProps<{
  model: ReturnType<typeof readForm>;
  context: ReadContext;
  port: MissionPagePort;
  phase: SetupPhase;
}>();
// A host token identifies this mounted draft. Same-token reads cannot reset it.
const model = props.model,
  context = props.context,
  port = missionFormPort(props.port);
</script>
<template>
  <div class="contents">
    <SetupOutcome :phase="phase" :href="model.form.actions.cancel.href" />
    <fieldset v-if="phase !== 'completed'" class="contents" :disabled="phase !== 'editing'">
      <TransportCreation v-bind="model" :context="context" :port="port" />
    </fieldset>
  </div>
</template>
