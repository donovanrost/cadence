<script setup lang="ts">
import { ref } from "vue";
import { ApButton, ApCallout, ApField, ApPanel } from "@/ui";
import { rejectionSentence, reviewChangeSet, type SubmitResult } from "./actions.ts";
import type { ChangeSet, ConfigState } from "./shapes.ts";

/** Independent review (mission policy): approve & apply, or send back with a comment. */
const props = defineProps<{ missionId: string; config: ConfigState; changeSet: ChangeSet }>();
const emit = defineEmits<{ result: [result: SubmitResult]; changed: [] }>();
const comment = ref("");
const busy = ref(false);
const failure = ref<string | null>(null);

async function decide(decision: "approve" | "send_back") {
  if (busy.value) return;
  busy.value = true;
  failure.value = null;
  try {
    const result = await reviewChangeSet(props.missionId, props.changeSet.id, {
      decision,
      comment: comment.value.trim(),
      expected_version: props.changeSet.version,
    });
    if (result.ok) emit("result", result.value);
    else {
      failure.value = rejectionSentence(result.error);
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
      <ApField v-model="comment" label="Comment" placeholder="Required to send back" />
      <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
      <ApButton
        variant="primary"
        size="commit"
        :disabled="busy"
        disabled-reason="Working…"
        @click="decide('approve')"
      >
        Approve &amp; apply as
        <span class="font-mono normal-case">r{{ config.head.revision + 1 }}</span>
      </ApButton>
      <ApButton
        :disabled="busy || comment.trim() === ''"
        disabled-reason="Add a comment for the author."
        @click="decide('send_back')"
        >Send back</ApButton
      >
    </div>
  </ApPanel>
</template>
