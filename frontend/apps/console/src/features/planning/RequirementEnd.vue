<script setup lang="ts">
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api";
import { failureOutcome } from "@/features/changes/index.ts";
import { useSession } from "@/shell";
import { ApButton, ApCallout, ApPanel, ApTextarea } from "@/ui";
import {
  endRequirement,
  fieldErrors,
  notActiveLine,
  type EndAction,
  type RequirementDetail,
} from "./requirements.ts";
import { fetchRequirementSupersedes, supersedeSentence } from "./supersedes.ts";

/** ux P4 Close… / Cancel…: each confirms with a required reason; both are final. */
const props = defineProps<{ missionId: string; requirement: RequirementDetail }>();
const emit = defineEmits<{ ended: [] }>();
const session = useSession();
const action = ref<EndAction | null>(null);
const reason = ref("");
const error = ref<string | null>(null);
const failure = ref<string | null>(null);
const busy = ref(false);
/** What each does, in the server's terms (ux; wording pending domain's answer, U20). */
const what: Readonly<Record<EndAction, { title: string; sentence: string; confirm: string }>> = {
  close: {
    title: "Close requirement",
    sentence: "Cadence stops planning for it from now. Passes already booked stay booked.",
    confirm: "Close it",
  },
  cancel: {
    title: "Cancel requirement",
    sentence: "It's withdrawn as if it was never needed. Nothing more is planned for it.",
    confirm: "Cancel it",
  },
};
const supersedes = useRemoteQuery(
  () => (action.value ? { missionId: props.missionId, requirementId: props.requirement.id } : null),
  fetchRequirementSupersedes,
);
const drafts = computed(() =>
  supersedes.state.value.status === "ready"
    ? supersedes.state.value.value.filter((d) => d.state !== "superseded")
    : [],
);
const blocked = computed(() =>
  busy.value ? "Working…" : reason.value.trim() === "" ? "Give a reason first." : null,
);
function open(a: EndAction) {
  action.value = a;
  error.value = failure.value = null;
}

async function confirm() {
  if (!action.value || blocked.value !== null) return;
  busy.value = true;
  try {
    const r = await endRequirement(props.missionId, props.requirement.id, action.value, {
      expected_version: props.requirement.version,
      reason: reason.value.trim(),
    });
    if (r.ok) return void emit("ended");
    error.value = fieldErrors(r.error)["reason"] ?? null;
    failure.value = error.value
      ? null
      : (notActiveLine(r.error) ?? failureOutcome(r.error, "changed").sentence);
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div v-if="!action" class="flex flex-wrap gap-2">
    <ApButton @click="open('close')">Close…</ApButton>
    <ApButton @click="open('cancel')">Cancel…</ApButton>
  </div>
  <ApPanel v-else index="Q9" :title="what[action].title">
    <div class="flex max-w-[640px] flex-col gap-3">
      <p class="m-0 text-md text-text-2">
        {{ what[action].sentence }} This is final: declare a new requirement to plan it again.
      </p>
      <ApCallout v-if="drafts.length > 0" tone="caution">{{
        supersedeSentence(
          drafts,
          requirement.version,
          session.user.id,
          action === "close" ? "Closing it" : "Canceling it",
        )
      }}</ApCallout>
      <ApTextarea v-model="reason" label="Reason" required :maxlength="2000" :error="error" />
      <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
      <div class="flex flex-wrap gap-2">
        <ApButton
          variant="danger"
          :disabled="blocked !== null"
          :disabled-reason="blocked ?? ''"
          @click="confirm"
          >{{ what[action].confirm }}</ApButton
        >
        <ApButton variant="ghost" @click="action = null">Back</ApButton>
      </div>
    </div>
  </ApPanel>
</template>
