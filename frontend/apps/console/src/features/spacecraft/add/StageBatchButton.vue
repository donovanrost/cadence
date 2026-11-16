<script setup lang="ts">
import { computed, ref } from "vue";
import { useRouter } from "vue-router";
import {
  failureOutcome,
  invalidOpDetails,
  refreshConfigState,
  stageChange,
  type FailureOutcome,
} from "@/features/changes/index.ts";
import { useMissionScope } from "@/shell";
import { ApButton, ApCallout, focusFirstConnected, plural } from "@/ui";
import { useDraft } from "./context.ts";
import { clearDraft } from "./draft.ts";
import { batchOps } from "./stage.ts";

/** The commit: stage the whole batch as one change in the mission's open change set. */
const props = defineProps<{ canManage: boolean }>();
const { proposal, profiles } = useDraft();
const scope = useMissionScope();
const router = useRouter();
const busy = ref(false);
const failure = ref<FailureOutcome | null>(null);

const ready = computed(() => {
  const p = proposal();
  return p.status === "ready" ? p : null;
});
const ops = computed(() =>
  ready.value ? batchOps(ready.value.report.rows, profiles(), ready.value.profileId) : null,
);
const reason = computed((): string | null => {
  if (!props.canManage) return "Only an organization admin can add spacecraft.";
  if (!ops.value) return "Complete the earlier steps first.";
  if (!ops.value.ok) return `Fix the NO-GO checks first. ${ops.value.message}`;
  return null;
});
const label = computed(() =>
  ready.value
    ? `Stage ${plural(ready.value.report.rows.length, "spacecraft", "spacecraft")}`
    : "Stage spacecraft",
);

/** a11y A5: Retry sits in the callout that stage() clears, so focus moves to Stage first. */
function retry() {
  focusFirstConnected(document.querySelector<HTMLElement>("[data-stage-batch]"));
  void stage();
}

async function stage() {
  const batch = ops.value;
  if (reason.value !== null || !batch?.ok || busy.value) return;
  busy.value = true;
  failure.value = null;
  const missionId = scope.value.mission.id;
  try {
    const result = await stageChange(missionId, {
      summary: batch.summary,
      source: { surface: "add_spacecraft" },
      ops: batch.ops,
    });
    if (result.ok) {
      clearDraft(missionId);
      refreshConfigState(missionId);
      await router.push({
        name: "setup.changes",
        query: { stagedSpacecraft: String(batch.ops.length) },
      });
      return;
    }
    const detail = invalidOpDetails(result.error);
    const row = detail ? ready.value?.report.rows[detail.index] : undefined;
    failure.value = detail
      ? {
          changed: false,
          sentence: `Nothing was staged. ${row?.name ?? `Row ${detail.index + 1}`}: ${detail.errors.map((e) => e.message).join("; ")}`,
        }
      : failureOutcome(result.error, "staged");
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApCallout v-if="failure" :tone="failure.changed === null ? 'caution' : 'crit'">
    {{ failure.sentence }} Your draft is kept.
    <template #action>
      <ApButton v-if="failure.changed === null" size="compact" :to="{ name: 'setup.changes' }"
        >Staged changes</ApButton
      >
      <ApButton v-else size="compact" @click="retry">Retry</ApButton>
    </template>
  </ApCallout>
  <ApButton
    variant="primary"
    size="commit"
    data-stage-batch
    :disabled="reason !== null || busy"
    :disabled-reason="reason ?? 'Staging…'"
    @click="stage"
    >{{ busy ? "Staging…" : label }}</ApButton
  >
  <p v-if="reason" class="m-0 text-sm text-text-3">{{ reason }}</p>
</template>
