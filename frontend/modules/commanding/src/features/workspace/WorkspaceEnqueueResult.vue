<script setup lang="ts">
import { computed } from "vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import type { WorkspaceOperation } from "./contracts";

const props = defineProps<{
  operation: Extract<WorkspaceOperation, { event: "enqueue" }>;
  pending: boolean;
  checking: boolean;
}>();
const emit = defineEmits<{ "check-result": [] }>();
const acknowledgement = computed(() => {
  const result = props.operation;
  if (result.status !== "completed" || result.receipt.kind !== "enqueue") return "";
  const requests = result.receipt.requests;
  const queued = requests.filter((request) => request.state === "queued").length;
  const approvals = requests.length - queued;
  if (!approvals) return queued === 1 ? "Command queued." : `${queued} commands queued.`;
  if (!queued)
    return approvals === 1
      ? "Approval requested."
      : `Approval requested for ${approvals} commands.`;
  return `${queued} queued · ${approvals} awaiting approval.`;
});
</script>

<template>
  <div id="workspace-enqueue-result" class="cw-actions cw-description" role="status">
    <template v-if="operation.status === 'unconfirmed'">
      <span v-if="pending">Submitting…</span>
      <template v-else>
        <span>Submission unconfirmed. Check the result before trying again.</span>
        <CadenceButton
          id="workspace-check-enqueue-result"
          size="xs"
          variant="outline"
          :disabled="checking"
          :loading="checking"
          @click="emit('check-result')"
          >Check result</CadenceButton
        >
      </template>
    </template>
    <span v-else-if="operation.status === 'rejected'">{{ operation.feedback }}</span>
    <span v-else>{{ acknowledgement }}</span>
  </div>
</template>
