<script setup lang="ts">
import { computed } from "vue";
import { canAdministerOrganization, useMissionScope, useSession } from "@/shell";
import { ApPanel } from "@/ui";
import { revisionBreaking } from "../breaking.ts";
import RolloutPanel from "../RolloutPanel.vue";
import type { ModelRevision } from "./api.ts";
import { rolloutGate } from "./rollout-gate.ts";

/**
 * U102 "Where" (#195): C3 Roll out to on a revision's page, under the Approval panel, by the same
 * rules as the import page's. Staging needs manage_mission, which the server grants to
 * organization admins (qa #4), so only they see it; the server enforces who may stage.
 */
const props = defineProps<{ revision: ModelRevision }>();
const scope = useMissionScope();
const session = useSession();
const canStage = computed(() => canAdministerOrganization(session, scope.value.organization));
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
