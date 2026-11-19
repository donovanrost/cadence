<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ref } from "vue";
import {
  failureOutcome,
  refreshConfigState,
  stageChange,
  type FailureOutcome,
} from "@/features/changes/index.ts";
import { ApButton, ApInlineConfirm, ApTag } from "@/ui";
import type { RoutingRule } from "./detail.ts";
import { olderRouteSummary, removeOlderRouteOp, removeOlderRouteSentence } from "./older-route.ts";

/**
 * ux U79: Remove… on an older route (origin 'legacy'), staged like any change, with the kit's
 * in-place confirm (focus on Cancel). A refusal is read under the sentence and the confirm stays
 * open. Once staged, the row says so and links the change set.
 */
const props = defineProps<{
  missionId: MissionId;
  rule: RoutingRule;
  spacecraftName: string | null;
  /** A removal of this route is already in the open set. */
  staged: boolean;
}>();
const confirming = ref(false);
const busy = ref(false);
const failure = ref<string | null>(null);
/** #405 (mms-ux): a refusal's way out, e.g. conversion_in_progress's 'Open change set' (U79). */
const failureLink = ref<FailureOutcome["link"] | null>(null);

async function remove() {
  if (busy.value) return;
  busy.value = true;
  failure.value = null;
  failureLink.value = null;
  try {
    const r = await stageChange(props.missionId, {
      summary: olderRouteSummary(props.rule, props.spacecraftName),
      source: { surface: "spacecraft" },
      ops: [removeOlderRouteOp(props.rule.id)],
    });
    if (!r.ok) {
      const outcome = failureOutcome(r.error, "staged");
      failure.value = outcome.sentence;
      failureLink.value = outcome.link ?? null;
      return;
    }
    confirming.value = false;
    refreshConfigState(props.missionId);
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <span v-if="staged" class="flex items-center justify-end gap-2">
    <ApTag label="Removal staged" />
    <ApButton size="compact" :to="{ name: 'setup.changes' }">Open change set</ApButton>
  </span>
  <ApInlineConfirm
    v-else
    v-model:open="confirming"
    action="Stage removal"
    :busy="busy"
    busy-reason="Staging…"
    :refusal="failure"
    @confirm="remove"
    @cancel="((failure = null), (failureLink = null))"
  >
    <template #trigger="{ attrs }">
      <ApButton size="compact" variant="ghost" v-bind="attrs">Remove…</ApButton>
    </template>
    {{ removeOlderRouteSentence(rule, spacecraftName) }}
    <template v-if="failureLink" #fields>
      <ApButton size="compact" class="self-start" :to="failureLink.to">{{
        failureLink.label
      }}</ApButton>
    </template>
  </ApInlineConfirm>
</template>
