<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ref } from "vue";
import { errorCode, failureOutcome } from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApField, ApPanel, formatShort } from "@/ui";
import { decidePolicy, pendingLine, type Policy } from "./policy.ts";

/** A pending policy version: approve or reject (reviewer ≠ author, enforced by the server). */
const props = defineProps<{ missionId: MissionId; policy: Policy }>();
const emit = defineEmits<{ decided: [] }>();
const comment = ref("");
const busy = ref(false);
const failure = ref<string | null>(null);
// The decision endpoint requires a comment (qa #21): block both actions until there is one.
const needComment = () =>
  comment.value.trim() === "" ? "Add a comment for the record first." : null;

async function decide(decision: "approve" | "reject") {
  const pending = props.policy.pending;
  if (!pending || busy.value || needComment()) return;
  busy.value = true;
  failure.value = null;
  try {
    const result = await decidePolicy(props.missionId, pending.version, {
      decision,
      comment: comment.value.trim(),
    });
    if (result.ok) emit("decided");
    else
      failure.value =
        errorCode(result.error) === "reviewer_is_author"
          ? "Nothing was changed. You saved this version, so another admin must approve it."
          : failureOutcome(result.error, "changed").sentence;
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel v-if="policy.pending" index="P5" title="Waiting for approval">
    <div class="flex flex-col gap-3">
      <p class="m-0 text-md text-text-3">
        {{ pendingLine(policy.pending, formatShort(new Date(policy.pending.requested_at))) }} It
        becomes active when another admin approves it.
      </p>
      <template v-if="policy.permissions.includes('planning.approve')">
        <ApField
          v-model="comment"
          label="Comment"
          required
          hint="Required: it's recorded with the decision."
        />
        <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
        <p v-if="needComment()" class="m-0 text-sm text-text-3">{{ needComment() }}</p>
        <div class="flex flex-wrap gap-2">
          <ApButton
            variant="primary"
            :disabled="busy || needComment() !== null"
            :disabled-reason="needComment() ?? 'Working…'"
            @click="decide('approve')"
            >Approve v{{ policy.pending.version }}</ApButton
          >
          <ApButton
            :disabled="busy || needComment() !== null"
            :disabled-reason="needComment() ?? 'Working…'"
            @click="decide('reject')"
            >Reject</ApButton
          >
        </div>
      </template>
    </div>
  </ApPanel>
</template>
