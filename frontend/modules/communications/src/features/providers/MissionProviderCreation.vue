<script setup lang="ts">
import type { MissionPagePort } from "@cadence/plugin-sdk/mission-pages";
import type { ReadContext } from "../../shared/read-contracts";
import type { SetupPhase } from "../../shared/mission-form-port";
import SetupOutcome from "../../shared/SetupOutcome.vue";
import type { ProviderNewModel } from "./form-validation";
import ProviderCreation from "./ProviderCreation.vue";
import { useMissionProviderPort } from "./mission-provider-port";
const props = defineProps<{
  model: ProviderNewModel;
  context: ReadContext;
  port: MissionPagePort;
  sequence: number;
  phase: SetupPhase;
}>();
const model = props.model,
  context = props.context;
const { state, port } = useMissionProviderPort(props.port, () => ({
  sequence: props.sequence,
  phase: props.phase,
}));
</script>
<template>
  <div>
    <SetupOutcome
      v-if="!state.pending"
      :phase="state.phase"
      :href="model.form.actions.cancel.href"
    />
    <fieldset v-if="phase !== 'completed'" class="contents" :disabled="state.phase !== 'editing'">
      <ProviderCreation :model="model" :context="context" :port="port" />
    </fieldset>
  </div>
</template>
