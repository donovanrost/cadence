<script setup lang="ts">
import type { MissionPagePort } from "@cadence/plugin-sdk/mission-pages";
import type { ReadContext } from "../../shared/read-contracts";
import type { SetupPhase } from "../../shared/mission-form-port";
import type { ProviderDetailModel } from "./provider-detail.contracts";
import ProviderDetail from "./ProviderDetail.vue";
import { useMissionProviderPort } from "./mission-provider-port";
const props = defineProps<{
  model: ProviderDetailModel;
  context: ReadContext;
  port: MissionPagePort;
  sequence: number;
  phase: SetupPhase;
}>();
const context = props.context;
const { state, port } = useMissionProviderPort(
  props.port,
  () => ({
    sequence: props.sequence,
    phase: props.phase,
    version: Number(props.model.provider.version.slice(1)),
  }),
  props.model.provider.provider_id,
);
</script>
<template>
  <div>
    <p
      v-if="!state.pending && state.phase !== 'editing'"
      id="mission-provider-outcome"
      role="status"
      class="mb-4 text-warning"
    >
      Further provider operations are locked. Refresh or review provider records to check the
      outcome.
    </p>
    <ProviderDetail
      :model="model"
      :context="context"
      :port="port"
      :locked="state.phase !== 'editing'"
    />
  </div>
</template>
