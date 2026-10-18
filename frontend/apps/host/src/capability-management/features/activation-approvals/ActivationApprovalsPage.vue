<script setup lang="ts">
import { computed, onBeforeUnmount, onErrorCaptured, ref, watch } from "vue";
import { useOpsHeader } from "@cadence/plugin-sdk/page-header";
import OpsActivationRequests from "./OpsActivationRequests.vue";
import { admitInbox, assertDecisionResult } from "./validation";
import type { DecisionInput, ReviewContext } from "./contracts";
const props = defineProps<{
  snapshot: unknown;
  context: ReviewContext;
  execute: (input: DecisionInput) => Promise<unknown>;
  refresh: () => Promise<void>;
  navigating?: boolean;
}>();
const admitted = computed(() => admitInbox(props.snapshot, props.context));
const busy = ref(false);
const message = ref("");
const failure = ref(false);
const crashed = ref(false);
let disposed = false;
useOpsHeader("/missions/:mission_id/ops/activations", () => ({
  description: "Review governed mission changes before Control applies them to runtime.",
  refresh: { run: props.refresh, pending: busy.value || props.navigating === true },
}));
onBeforeUnmount(() => {
  disposed = true;
});
onErrorCaptured(() => {
  crashed.value = true;
  return false;
});
watch(
  () => props.snapshot,
  () => {
    crashed.value = false;
  },
);
async function decide(input: DecisionInput) {
  if (busy.value || props.navigating || !admitted.value || disposed) return;
  busy.value = true;
  message.value = "";
  failure.value = false;
  try {
    const result = await props.execute(input);
    if (disposed) return;
    assertDecisionResult(result, input);
    if (result.status === "ok") {
      failure.value = result.data.outcome === "application_needs_review";
      message.value =
        result.data.outcome === "rejected"
          ? "Request rejected."
          : result.data.outcome === "applied"
            ? "Request approved and applied."
            : "Request approved. Runtime application needs review; do not submit another approval.";
    } else if (result.status === "invalid") {
      failure.value = true;
      message.value = result.message;
    } else throw new Error("Unavailable");
  } catch {
    if (!disposed) {
      failure.value = true;
      message.value = "The decision could not be confirmed. Refresh the inbox before trying again.";
    }
  } finally {
    if (!disposed) busy.value = false;
  }
}
</script>
<template>
  <section id="activation-approvals-host" :aria-busy="busy">
    <div v-if="busy || message" class="mb-4">
      <p v-if="busy" id="activation-review-pending" role="status">Recording decision…</p>
      <p
        v-else-if="message"
        id="activation-review-result"
        :role="failure ? 'alert' : 'status'"
        :class="failure ? 'text-warning' : 'text-success'"
      >
        {{ message }}
      </p>
    </div>
    <p
      v-if="!admitted || crashed"
      id="activation-inbox-unavailable"
      role="alert"
      class="card border border-warning/40 bg-base-200 p-6"
    >
      Activation approvals could not be loaded. The rest of Cadence remains available.
    </p>
    <OpsActivationRequests
      v-else
      v-bind="admitted.data"
      :disabled="busy || navigating"
      @decide="decide"
    />
  </section>
</template>
