<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref, watch } from "vue";
import { isError, type RemoteState } from "@/api";
import { ApButton, ApField, ApPanel } from "@/ui";
import { reviewChangeSet, type Preview, type SubmitResult } from "./actions.ts";
import { checksRefusal, HOLD_STANDS } from "./checkRefusals.ts";
import FailureOutcomeCallout from "./FailureOutcomeCallout.vue";
import { blockingReason } from "./itemLines.ts";
import { inUseMark, refusalOutcome, type InUseMark, type RefusalOutcome } from "./refusals.ts";
import { reviewBlocked } from "./review-block.ts";
import type { ChangeSet, ConfigState } from "./shapes.ts";

/**
 * Independent review (mission policy): approve & apply, or send back. The server takes a comment
 * for both decisions (changes.md review: 422 comment_required; qa 11-16), so both wait for one.
 */
const props = defineProps<{
  missionId: MissionId;
  config: ConfigState;
  changeSet: ChangeSet;
  /** The set's checks (K2), for U79's blocking hold up front (#376). */
  preview: RemoteState<Preview>;
}>();
const emit = defineEmits<{
  result: [result: SubmitResult];
  changed: [];
  /** U82: the archive row an apply-time in-use refusal is about, or null to clear it. */
  inUse: [mark: InUseMark | null];
}>();
const comment = ref("");
const busy = ref(false);
const failure = ref<RefusalOutcome | null>(null);
const NEEDS_COMMENT = "Add a comment first. It's recorded with your decision.";
/** #320 (U97): the server says this viewer can't review; both decisions say why before the click. */
const blocked = computed(() => reviewBlocked(props.changeSet));
const reasonFor = (needsComment: string) =>
  busy.value ? "Working…" : (blocked.value?.line ?? needsComment);

/**
 * #376 (U79): a blocking hold stops Approve, never Send back. Up front from the checks; after a
 * 409 holds_blocking, until a reload's checks show the hold cleared (the server's checks may
 * have seen it before the console's did). #395: only checks requested at or after the refusal
 * count as that reload; a read already in flight then carries the older answer.
 */
const refusedForHoldAt = ref<Date | null>(null);
const holdInChecks = computed(
  () => props.preview.status === "ready" && blockingReason(props.preview.value) !== null,
);
watch(
  () => props.preview,
  (checks) => {
    const since = refusedForHoldAt.value;
    if (since === null || checks.status !== "ready" || blockingReason(checks.value) !== null)
      return;
    if (checks.requestedAt && checks.requestedAt >= since) refusedForHoldAt.value = null;
  },
);
const holdStands = computed(() => holdInChecks.value || refusedForHoldAt.value !== null);
const approveReason = computed(() =>
  busy.value
    ? "Working…"
    : (blocked.value?.line ?? (holdStands.value ? HOLD_STANDS : NEEDS_COMMENT)),
);

async function decide(decision: "approve" | "send_back") {
  if (busy.value) return;
  busy.value = true;
  failure.value = null;
  emit("inUse", null);
  try {
    const result = await reviewChangeSet(props.missionId, props.changeSet.id, {
      decision,
      comment: comment.value.trim(),
      expected_version: props.changeSet.version,
    });
    if (result.ok) emit("result", result.value);
    else {
      if (decision === "approve" && isError(result.error, "holds_blocking"))
        refusedForHoldAt.value = new Date();
      failure.value =
        (decision === "approve" ? checksRefusal(result.error, "approve") : null) ??
        refusalOutcome(result.error, "changed");
      emit("inUse", inUseMark(failure.value));
      emit("changed");
    }
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel index="K3" title="Review">
    <div class="flex flex-col gap-4">
      <p class="m-0 text-md text-text-3">
        Submitted by {{ changeSet.submitted_by?.name ?? "—" }}: “{{ changeSet.reason ?? "" }}”
      </p>
      <p v-if="blocked" data-review-blocked class="m-0 text-md text-text-3">{{ blocked.line }}</p>
      <details v-if="blocked?.code" class="text-sm">
        <summary class="ap-label cursor-pointer">Technical details</summary>
        <p class="m-0 mt-1 font-mono text-xs text-text-3">
          review_blocked_reason: {{ blocked.code }}
        </p>
      </details>
      <ApField
        v-model="comment"
        label="Comment"
        required
        hint="Recorded with your decision, whether you approve or send it back."
      />
      <FailureOutcomeCallout v-if="failure" :outcome="failure" />
      <ApButton
        variant="primary"
        size="commit"
        :disabled="busy || blocked !== null || holdStands || comment.trim() === ''"
        :disabled-reason="approveReason"
        @click="decide('approve')"
      >
        Approve &amp; apply as
        <span class="font-mono normal-case">r{{ config.head.revision + 1 }}</span>
      </ApButton>
      <p v-if="holdStands && !blocked" data-hold-stands class="m-0 text-sm text-text-3">
        {{ HOLD_STANDS }}
      </p>
      <ApButton
        :disabled="busy || blocked !== null || comment.trim() === ''"
        :disabled-reason="reasonFor('Add a comment for the author.')"
        @click="decide('send_back')"
        >Send back</ApButton
      >
    </div>
  </ApPanel>
</template>
