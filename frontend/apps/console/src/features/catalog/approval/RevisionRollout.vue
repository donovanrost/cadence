<script setup lang="ts">
import { computed } from "vue";
import { useMissionScope } from "@/shell";
import { useCanStage } from "@/features/changes/index.ts";
import { ApPanel } from "@/ui";
import { revisionBreaking } from "../breaking.ts";
import RolloutPanel from "../RolloutPanel.vue";
import type { ModelRevision } from "./api.ts";
import { rolloutGate } from "./rollout-gate.ts";

/**
 * U102 "Where" (#195): C3 Roll out to on a revision's page, under the Approval panel, by the same
 * rules as the import page's. Shown to those who may stage (config.stage, operate_mission, #1160);
 * the server enforces who may stage.
 */
const props = defineProps<{ revision: ModelRevision }>();
const scope = useMissionScope();
const canStage = useCanStage(scope.value.mission.id);
const gate = computed(() => rolloutGate(props.revision));
</script>

<template>
  <template v-if="canStage">
    <RolloutPanel
      v-if="gate.kind === 'rollout'"
      :revision="gate.revision"
      :breaking="revisionBreaking(gate.catalogRevision)"
    />
    <ApPanel v-else-if="gate.kind === 'line'" index="C3" title="Roll out to">
      <p data-rollout-gate class="m-0 text-md text-text-2">{{ gate.line }}</p>
    </ApPanel>
  </template>
</template>
