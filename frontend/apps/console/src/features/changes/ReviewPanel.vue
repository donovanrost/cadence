<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ref } from "vue";
import { ApButton, ApField, ApPanel } from "@/ui";
import { reviewChangeSet, type SubmitResult } from "./actions.ts";
import FailureOutcomeCallout from "./FailureOutcomeCallout.vue";
import { inUseMark, refusalOutcome, type InUseMark, type RefusalOutcome } from "./refusals.ts";
import type { ChangeSet, ConfigState } from "./shapes.ts";

/**
 * Independent review (mission policy): approve & apply, or send back. The server takes a comment
 * for both decisions (changes.md review: 422 comment_required; qa 11-16), so both wait for one.
 */
const props = defineProps<{ missionId: MissionId; config: ConfigState; changeSet: ChangeSet }>();
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
      failure.value = refusalOutcome(result.error, "changed");
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
        :disabled="busy || comment.trim() === ''"
        :disabled-reason="busy ? 'Working…' : NEEDS_COMMENT"
        @click="decide('approve')"
      >
        Approve &amp; apply as
        <span class="font-mono normal-case">r{{ config.head.revision + 1 }}</span>
      </ApButton>
      <ApButton
        :disabled="busy || comment.trim() === ''"
        :disabled-reason="busy ? 'Working…' : 'Add a comment for the author.'"
        @click="decide('send_back')"
        >Send back</ApButton
      >
    </div>
  </ApPanel>
</template>
