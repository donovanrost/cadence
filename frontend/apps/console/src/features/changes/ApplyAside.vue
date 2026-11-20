<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref, watch } from "vue";
import { isError, type RemoteState } from "@/api";
import { useMissionScope } from "@/shell";
import { ApButton, ApCallout, ApField, ApPanel } from "@/ui";
import ApplyTiles from "./ApplyTiles.vue";
import { cannotApplyLine, noGoReason } from "./apply-reasons.ts";
import { NOTHING_RUNNING } from "./nothingRunning.ts";
import FailureOutcomeCallout from "./FailureOutcomeCallout.vue";
import { submitChangeSet, type Preview, type SubmitResult } from "./actions.ts";
import { applyRefusal } from "./apply-refusals.ts";
import { checksRefusal } from "./checkRefusals.ts";
import { blockingReason } from "./itemLines.ts";
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
  /** K9: the Authors line reads the viewer as "you". */
  viewerId?: string | null | undefined;
}>();
const emit = defineEmits<{
  result: [result: SubmitResult];
  changed: [];
  /** U82: the archive row an apply-time in-use refusal is about, or null to clear it. */
  inUse: [mark: InUseMark | null];
}>();

const scope = useMissionScope();
const why = ref("");
const whyError = ref<string | null>(null);
watch(why, () => (whyError.value = null));
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
    return cannotApplyLine(scope.value.mission.name);
  if (verdict.value === null) {
    if (props.held === null) return "Waiting for checks.";
    return props.preview.status === "failed" ? NOT_RUN_REASON : RECHECKING_REASON;
  }
  if (verdict.value === "no_go" && props.preview.status === "ready")
    return noGoReason(props.preview.value, needsReview.value ? "request_review" : "apply");
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
      // #376: submit's 503 preview_failed is opened by the act the button named (#374).
      // #310 (ca-ux, U79): an apply refusal opens "Not applied:", per code; a missing reason is
      // the Why field's own message, not a callout.
      if (isError(result.error, "reason_required")) {
        whyError.value = "Say why (10 characters or more).";
        failure.value = null;
      } else {
        const act = needsReview.value ? "request_review" : "apply";
        failure.value =
          checksRefusal(result.error, act) ??
          applyRefusal(result.error, act) ??
          refusalOutcome(result.error, "applied");
      }
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
      <ApplyTiles
        :staged="changeSet.staged_count"
        :outcome="preview.status === 'ready' ? preview.value.outcome : undefined"
        :authors="changeSet.authors"
        :viewer-id="viewerId ?? null"
      />
      <ApField v-model="why" label="Why" :placeholder="placeholder" required :error="whyError" />
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
