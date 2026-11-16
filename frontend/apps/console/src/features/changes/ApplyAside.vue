<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref, watch } from "vue";
import type { RemoteState } from "@/api";
import { ApButton, ApCallout, ApField, ApPanel, ApStatTile } from "@/ui";
import { NOTHING_RUNNING } from "./nothingRunning.ts";
import FailureOutcomeCallout from "./FailureOutcomeCallout.vue";
import { blockingReason, submitChangeSet, type Preview, type SubmitResult } from "./actions.ts";
import { inUseMark, refusalOutcome, type InUseMark, type RefusalOutcome } from "./refusals.ts";
import { holdsKey, NOT_RUN_REASON, RECHECKING_REASON, type HeldChecks } from "./checks-view.ts";
import { whyPlaceholder } from "./holds.ts";
import type { ChangeSet, ConfigState } from "./shapes.ts";

/** K3 Apply: why (required), holds acknowledgement, apply or request review (mission policy). */
const props = defineProps<{
  missionId: MissionId;
  config: ConfigState;
  changeSet: ChangeSet;
  preview: RemoteState<Preview>;
  /** ux B4: the previous checks while the current set's re-run (or failed). */
  held: HeldChecks | null;
}>();
const emit = defineEmits<{
  result: [result: SubmitResult];
  changed: [];
  /** U82: the archive row an apply-time in-use refusal is about, or null to clear it. */
  inUse: [mark: InUseMark | null];
}>();

const why = ref("");
const acknowledged = ref(false);
// ux B4: re-run checks clear the holds acknowledgement only if what they hold changed.
let ackedHolds: string | null = null;
watch(
  () => (props.preview.status === "ready" ? holdsKey(props.preview.value) : null),
  (key) => {
    if (key === null) return;
    if (ackedHolds !== null && key !== ackedHolds) acknowledged.value = false;
    ackedHolds = key;
  },
  { immediate: true },
);
const busy = ref(false);
/** With its link, e.g. U65 'Open the report'. */
const failure = ref<RefusalOutcome | null>(null);
const next = computed(() => props.config.head.revision + 1);
const needsReview = computed(() => props.changeSet.approval_required === true);
const nothingRunning = computed(
  () => props.preview.status === "ready" && props.preview.value.has_active_configuration === false,
);
const verdict = computed(() =>
  props.preview.status === "ready" ? props.preview.value.verdict : null,
);

/** #65: a blocking hold can't be acknowledged away, so the checkbox doesn't show for it. */
const blocking = computed(() =>
  props.preview.status === "ready" ? blockingReason(props.preview.value) : null,
);
/** ux U40/U43: one acknowledgeable HOLD names what to justify; several share one placeholder. */
const placeholder = computed(
  () =>
    (props.preview.status === "ready" ? whyPlaceholder(props.preview.value) : null) ??
    "Goes in the revision and the audit log",
);
const blocked = computed((): string | null => {
  if (props.changeSet.state === "in_review")
    return `r${next.value} is in review; staging is paused.`;
  if (!props.config.permissions.has("config.apply"))
    return "You can stage changes but not apply them.";
  if (verdict.value === null) {
    if (props.held === null) return "Waiting for checks.";
    return props.preview.status === "failed" ? NOT_RUN_REASON : RECHECKING_REASON;
  }
  if (verdict.value === "no_go") return "A NO-GO check blocks apply. Fix it first.";
  if (blocking.value) return blocking.value;
  if (verdict.value === "hold" && !acknowledged.value) return "Acknowledge the holds first.";
  if (why.value.trim().length < 10) return "Say why (10 characters or more).";
  return null;
});

async function apply() {
  if (blocked.value !== null || busy.value) return;
  busy.value = true;
  failure.value = null;
  emit("inUse", null);
  try {
    const result = await submitChangeSet(props.missionId, props.changeSet.id, {
      reason: why.value.trim(),
      expected_version: props.changeSet.version,
      acknowledged_holds: acknowledged.value,
    });
    if (result.ok) emit("result", result.value);
    else {
      failure.value = refusalOutcome(result.error, "applied");
      emit("inUse", inUseMark(failure.value));
      emit("changed");
    }
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel index="K3" title="Apply">
    <div class="flex flex-col gap-4">
      <div class="grid grid-cols-2 gap-px border border-hairline bg-hairline">
        <ApStatTile label="Changes" :value="changeSet.staged_count" />
        <ApStatTile label="Authors" :value="changeSet.authors.length" />
      </div>
      <ApField v-model="why" label="Why" :placeholder="placeholder" required />
      <label
        v-if="verdict === 'hold' && !blocking"
        class="flex items-center gap-2 text-md text-readout"
      >
        <input
          v-model="acknowledged"
          type="checkbox"
          class="size-4 accent-[var(--color-readout)]"
        />
        I've read the holds
      </label>
      <FailureOutcomeCallout v-if="failure" :outcome="failure" />
      <!-- U93: only when the preview says no activation exists on the mission. -->
      <ApCallout v-if="nothingRunning" tone="info">{{ NOTHING_RUNNING }}</ApCallout>
      <ApButton
        variant="primary"
        size="commit"
        :disabled="blocked !== null || busy"
        :disabled-reason="blocked ?? 'Applying…'"
        @click="apply"
      >
        <template v-if="busy">Applying…</template>
        <template v-else-if="needsReview">Request review</template>
        <template v-else
          >Apply as <span class="font-mono normal-case">r{{ next }}</span></template
        >
      </ApButton>
      <p v-if="blocked" class="m-0 text-sm text-text-3">{{ blocked }}</p>
      <p class="m-0 font-mono text-xs text-text-4 uppercase">
        Atomic · all or nothing ·
        <span class="normal-case">r{{ config.head.revision }}</span> kept for rollback
      </p>
    </div>
  </ApPanel>
</template>
