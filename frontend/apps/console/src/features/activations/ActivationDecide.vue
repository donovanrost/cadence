<script setup lang="ts">
import { computed, ref } from "vue";
import { fieldErrors } from "@/api";
import { RouterLink } from "vue-router";
import { ApButton, ApCallout, ApPanel, ApTextarea } from "@/ui";
import { approveRefusal, type ApproveRefusal } from "./approveRefusal.ts";
import {
  decide,
  decidedLine,
  decideFailure,
  isRequester as requestedBy,
  mayDecide,
  type ActivationDetail,
  type DetailKey,
  type Verb,
  type Viewer,
  WITHDRAW_LIVE,
} from "./api.ts";

/** The reviewer's Approve and apply / Reject, or the requester's Withdraw…; a reason is required. */
const props = defineProps<{
  requestKey: DetailKey;
  request: ActivationDetail;
  viewer: Viewer;
}>();
const emit = defineEmits<{ decided: [note: { tone: "nominal" | "caution"; text: string }] }>();
const isRequester = computed(() => requestedBy(props.request, props.viewer));
/** Approve/reject through the one gate; Withdraw only once domain has it. */
const canAct = computed(
  () => mayDecide(props.request, props.viewer) || (isRequester.value && WITHDRAW_LIVE),
);
const reason = ref("");
const error = ref<string | null>(null);
const failure = ref<string | null>(null);
/** U95: an Approve the preflight refused; nothing was recorded, so Approve stays off with it. */
const refused = ref<ApproveRefusal | null>(null);
const busy = ref<Verb | null>(null);
const blocked = computed(() =>
  busy.value ? "Working…" : reason.value.trim() === "" ? "Give a reason first." : null,
);
const approveBlocked = computed(() => (refused.value?.final ? refused.value.text : blocked.value));
async function go(verb: Verb) {
  if (blocked.value !== null) return;
  busy.value = verb;
  try {
    const r = await decide(props.requestKey, verb, reason.value.trim());
    if (r.ok) return void emit("decided", decidedLine(verb, r.value));
    error.value = fieldErrors(r.error)["reason"] ?? null;
    refused.value = verb === "approve" && !error.value ? approveRefusal(r.error) : null;
    failure.value = error.value || refused.value ? null : decideFailure(r.error);
  } finally {
    busy.value = null;
  }
}
</script>

<template>
  <ApPanel index="R2" :title="isRequester ? 'Your request' : 'Decide'">
    <div class="flex max-w-[640px] flex-col gap-3">
      <p v-if="isRequester" class="m-0 text-md text-text-2">
        You requested this. Someone else approves it.
      </p>
      <p v-else class="m-0 text-md text-text-2">
        Approving applies it to the mission now. Rejecting leaves things as they are.
      </p>
      <ApTextarea
        v-if="canAct"
        v-model="reason"
        label="Reason"
        required
        :maxlength="4096"
        :placeholder="isRequester ? 'Why you\'re withdrawing it' : undefined"
        :error="error"
      />
      <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
      <ApCallout v-if="refused" tone="crit">
        {{ refused.text }}
        <details v-if="refused.code" class="mt-1 text-xs text-text-3">
          <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
          <p class="m-0 font-mono">{{ refused.code }}</p>
        </details>
        <template v-if="refused.link" #action
          ><RouterLink
            :to="refused.link.to"
            class="text-sm text-readout underline hover:text-bright"
            >{{ refused.link.label }}</RouterLink
          ></template
        >
      </ApCallout>
      <div v-if="canAct" class="flex flex-wrap gap-2">
        <template v-if="mayDecide(request, viewer)">
          <ApButton
            variant="primary"
            :disabled="approveBlocked !== null"
            :disabled-reason="approveBlocked ?? ''"
            @click="go('approve')"
            >Approve and apply</ApButton
          >
          <ApButton
            :disabled="blocked !== null"
            :disabled-reason="blocked ?? ''"
            @click="go('reject')"
            >Reject</ApButton
          >
        </template>
        <ApButton
          v-if="isRequester && WITHDRAW_LIVE"
          variant="danger"
          :disabled="blocked !== null"
          :disabled-reason="blocked ?? ''"
          @click="go('withdraw')"
          >Withdraw request</ApButton
        >
      </div>
    </div>
  </ApPanel>
</template>
