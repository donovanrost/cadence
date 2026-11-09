<script setup lang="ts">
import { ref } from "vue";
import { failureOutcome } from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApField, ApPanel, formatShort } from "@/ui";
import { decidePolicy, type Policy } from "./policy.ts";

/** A pending policy version: approve or reject (reviewer ≠ author, enforced by the server). */
const props = defineProps<{ missionId: string; policy: Policy }>();
const emit = defineEmits<{ decided: [] }>();
const comment = ref("");
const busy = ref(false);
const failure = ref<string | null>(null);

async function decide(decision: "approve" | "reject") {
  const pending = props.policy.pending;
  if (!pending || busy.value) return;
  busy.value = true;
  failure.value = null;
  try {
    const result = await decidePolicy(props.missionId, pending.version, {
      decision,
      comment: comment.value.trim(),
    });
    if (result.ok) emit("decided");
    else failure.value = failureOutcome(result.error, "changed").sentence;
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel v-if="policy.pending" index="P5" title="Waiting for approval">
    <div class="flex flex-col gap-3">
      <p class="m-0 text-md text-text-3">
        Policy v{{ policy.pending.version }} was saved
        {{ policy.pending.requested_by ? `by ${policy.pending.requested_by.name} ` : ""
        }}{{ formatShort(new Date(policy.pending.requested_at)) }}. It becomes active when another
        admin approves it.
      </p>
      <template v-if="policy.permissions.includes('planning.approve')">
        <ApField v-model="comment" label="Comment" />
        <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
        <div class="flex flex-wrap gap-2">
          <ApButton
            variant="primary"
            :disabled="busy"
            disabled-reason="Working…"
            @click="decide('approve')"
            >Approve v{{ policy.pending.version }}</ApButton
          >
          <ApButton :disabled="busy" disabled-reason="Working…" @click="decide('reject')"
            >Reject</ApButton
          >
        </div>
      </template>
    </div>
  </ApPanel>
</template>
