<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, reactive, ref, watch } from "vue";
import { useRemoteQuery } from "@/api";
import { failureOutcome } from "@/features/changes/index.ts";
import { useSession } from "@/shell";
import { ApButton, ApCallout, ApInlineConfirm, ApTextarea } from "@/ui";
import {
  endRequirement,
  fieldErrors,
  notActiveLine,
  occurrenceScope,
  type EndAction,
  type RequirementDetail,
} from "./requirements.ts";
import { fetchRequirementSupersedes, supersedeSentence } from "./supersedes.ts";

/**
 * ux P4 Close… / Cancel…: each confirms in place with a required reason; both are final. The kit's
 * ApInlineConfirm (design-language §7): the Reason takes focus, Esc backs out to the trigger, one
 * open at a time, a refusal is read under the sentence and it stays open.
 */
const props = defineProps<{
  missionId: MissionId;
  requirement: RequirementDetail;
  /** A template's occurrence: the sheet leads with its scope (ux). */
  occurrence?: Readonly<{ day: string; template: string }> | null;
}>();
const emit = defineEmits<{ ended: [] }>();
const session = useSession();
const opened = reactive<Record<EndAction, boolean>>({ close: false, cancel: false });
const action = computed<EndAction | null>(() =>
  opened.close ? "close" : opened.cancel ? "cancel" : null,
);
const actions = ["close", "cancel"] as const;
const reason = ref("");
const error = ref<string | null>(null);
const failure = ref<string | null>(null);
const busy = ref(false);
/**
 * What each does, in the server's terms (U20, domain): today both stop planning and keep booked
 * passes; only the recorded state differs. Drafts and pending plans using it read superseded.
 */
const what: Readonly<
  Record<
    EndAction,
    { opener: string; question: string; sentence: string; confirm: string; busy: string }
  >
> = {
  close: {
    opener: "Close…",
    question: "Close this requirement?",
    busy: "Closing…",
    sentence:
      "Use this when it's done or no longer needed. Cadence stops planning for it. Passes already booked stay booked.",
    confirm: "Close requirement",
  },
  cancel: {
    opener: "Cancel…",
    question: "Cancel this requirement?",
    busy: "Canceling…",
    sentence:
      "Use this when it was a mistake. Withdraws it: nothing more is planned for it. Passes already booked stay booked.",
    confirm: "Cancel requirement",
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
const blocked = computed(() => (reason.value.trim() === "" ? "Give a reason first." : null));
watch(action, () => {
  error.value = failure.value = null;
});

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
  <div class="flex flex-wrap gap-2">
    <ApInlineConfirm
      v-for="a in actions"
      :key="a"
      v-model:open="opened[a]"
      :action="what[a].confirm"
      :busy="busy"
      :busy-reason="what[a].busy"
      :blocked="blocked"
      :refusal="failure"
      @confirm="confirm"
    >
      <template #trigger="{ attrs }">
        <ApButton v-bind="attrs">{{ what[a].opener }}</ApButton>
      </template>
      {{ what[a].question }}
      <template v-if="occurrence"
        >{{ occurrenceScope(a, occurrence).lead }} {{ what[a].sentence }}
        {{ occurrenceScope(a, occurrence).final }}</template
      >
      <template v-else
        >{{ what[a].sentence }} This is final: declare a new requirement to plan it again.</template
      >
      <template #fields>
        <ApCallout v-if="drafts.length > 0" tone="caution">{{
          supersedeSentence(
            drafts,
            requirement.version,
            session.user.id,
            a === "close" ? "Closing it" : "Canceling it",
          )
        }}</ApCallout>
        <ApTextarea v-model="reason" label="Reason" required :maxlength="2000" :error="error" />
      </template>
    </ApInlineConfirm>
  </div>
</template>
