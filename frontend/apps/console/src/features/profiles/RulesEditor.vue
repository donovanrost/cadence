<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { useRouter } from "vue-router";
import { useRemoteQuery, type ApiError } from "@/api";
import {
  FailureOutcomeCallout,
  failureOutcome,
  invalidOpDetails,
  previewOps,
  refreshConfigState,
  stageChange,
  type StageOp,
  useStageFailure,
} from "@/features/changes/index.ts";
import { fetchStations } from "@/features/stations/index.ts";
import {
  ApButton,
  ApCallout,
  ApPanel,
  ApRemote,
  ApSegmented,
  focusAfterRemove,
  plural,
} from "@/ui";
import RuleForm from "./RuleForm.vue";
import type { ProfileDetail } from "./detail.ts";
import {
  draftProblems,
  newRule,
  rulePathWords,
  toDocument,
  toDrafts,
  type RuleDraft,
} from "./rulesDraft.ts";
import { describePreview } from "./sectionEdit.ts";

/** P2 edit: the whole rule list as one staged change at `routing_rules` (domain P2). */
const props = defineProps<{ missionId: MissionId; detail: ProfileDetail }>();
const emit = defineEmits<{ close: [] }>();
const router = useRouter();
const stations = useRemoteQuery(() => props.missionId, fetchStations);
const drafts = ref<RuleDraft[]>(toDrafts(props.detail.rules));
// a11y A5: Remove rule takes itself; land on the next rule's Remove, else Add rule.
const rulesBox = ref<HTMLElement | null>(null);
function removeRule(i: number) {
  drafts.value.splice(i, 1);
  void focusAfterRemove(rulesBox.value, "[data-remove-rule]", i, () =>
    rulesBox.value?.querySelector<HTMLElement>("[data-add-rule]"),
  );
}
const rollout = ref<"all" | "none">("all");
const busy = ref(false);
const outcome = ref<{ tone: "nominal" | "caution" | "crit"; text: string } | null>(null);
/** A refused or unclear Stage, with its link (e.g. U79 'Open change set'). */
const failure = useStageFailure([drafts, rollout]);
const problems = computed(() => draftProblems(drafts.value));
if (drafts.value.length === 0) drafts.value.push(newRule([]));

/**
 * A rejection opens with the act (designers §3, #307) and names each rule and field by its label
 * (Profile.md P2), never the server's path (`routing_rules.0.stations`).
 */
function rejected(error: ApiError, verb: "staged" | "changed") {
  const detail = invalidOpDetails(error);
  if (!detail) return failureOutcome(error, verb).sentence;
  const why = detail.errors.map((e) => `${rulePathWords(e.path, drafts.value)}: ${e.message}`);
  return `Not ${verb}: ${why.join(" · ")}`;
}

const op = (): StageOp => ({
  kind: "spacecraft_profile",
  action: "update",
  entity_id: props.detail.profile.id,
  changes: [{ path: "routing_rules", value: toDocument(drafts.value) }],
  options: { rollout: rollout.value },
});

async function check() {
  if (problems.value.length > 0 || busy.value) return;
  busy.value = true;
  failure.value = null;
  try {
    const result = await previewOps(
      { missionId: props.missionId, ops: [op()] },
      new AbortController().signal,
    );
    outcome.value = result.ok
      ? describePreview(result.value)
      : { tone: "crit", text: rejected(result.error, "changed") };
  } finally {
    busy.value = false;
  }
}
async function stage() {
  if (problems.value.length > 0 || busy.value) return;
  busy.value = true;
  failure.value = null;
  try {
    const result = await stageChange(props.missionId, {
      summary: `${props.detail.profile.name} · routing rules (${plural(drafts.value.length, "rule")})`,
      source: { surface: "profile_routing" },
      ops: [op()],
    });
    if (!result.ok) return void (failure.value = failureOutcome(result.error, "staged"));
    refreshConfigState(props.missionId);
    await router.push({ name: "setup.changes" });
  } finally {
    busy.value = false;
  }
}
const rolloutOptions = [
  { value: "all", label: "All spacecraft on this profile" },
  { value: "none", label: "New version only" },
] as const;
</script>

<template>
  <ApPanel index="P2" title="Edit routing rules" :meta="plural(drafts.length, 'rule')">
    <ApRemote
      :state="stations.state.value"
      loading-label="Loading stations…"
      @retry="stations.refetch"
    >
      <template #default="{ value: stationList }">
        <div ref="rulesBox" class="flex flex-col gap-4">
          <RuleForm
            v-for="(_, i) in drafts"
            :key="drafts[i]?.id ?? i"
            v-model="drafts[i]!"
            :index="i"
            :stations="stationList"
            @remove="removeRule(i)"
          />
          <div>
            <ApButton size="compact" data-add-rule @click="drafts.push(newRule(drafts))"
              >Add rule</ApButton
            >
          </div>
          <ApSegmented v-model="rollout" label="Roll out to" :options="rolloutOptions" />
          <ApCallout v-if="problems.length > 0" tone="caution">{{ problems.join(" ") }}</ApCallout>
          <ApCallout v-if="outcome" :tone="outcome.tone">{{ outcome.text }}</ApCallout>
          <FailureOutcomeCallout v-if="failure" :outcome="failure" />
          <div class="flex flex-wrap gap-2">
            <ApButton
              :disabled="busy || problems.length > 0"
              :disabled-reason="busy ? 'Working…' : (problems[0] ?? '')"
              @click="check"
              >Check with the server</ApButton
            >
            <ApButton
              variant="primary"
              :disabled="busy || problems.length > 0"
              :disabled-reason="busy ? 'Working…' : (problems[0] ?? '')"
              @click="stage"
              >Stage rule change</ApButton
            >
            <ApButton variant="ghost" @click="emit('close')">Cancel</ApButton>
          </div>
        </div>
      </template>
    </ApRemote>
  </ApPanel>
</template>
