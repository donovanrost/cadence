<script setup lang="ts">
import { computed, ref } from "vue";
import { useRouter } from "vue-router";
import { useRemoteQuery } from "@/api";
import {
  FailureOutcomeCallout,
  failureOutcome,
  refreshConfigState,
  stageChange,
  type FailureOutcome,
} from "@/features/changes/index.ts";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import { ApButton, ApPanel } from "@/ui";
import { breakingWords, type Breaking } from "./breaking.ts";
import RolloutBreaking from "./RolloutBreaking.vue";
import RolloutChoose from "./RolloutChoose.vue";
import RolloutDryRun from "./RolloutDryRun.vue";
import {
  fetchRollout,
  rolloutMoves,
  rolloutOps,
  stageLabel,
  type RolloutChoice,
} from "./rollout.ts";
import { useRolloutDryRun } from "./useRolloutDryRun.ts";

/** C3 Roll out to (Catalog.md, #65): stage this revision by profile or on a few spacecraft. */
const props = defineProps<{
  revision: Readonly<{ id: string; number: number }>;
  /** U102: what the server knows about breaking changes; staging needs them checked (no C2 yet). */
  breaking: Breaking;
}>();
const breakingLine = computed(() => breakingWords(props.breaking, props.revision.number));
const breakingCount = computed(() => (props.breaking.kind === "count" ? props.breaking.count : 0));
const router = useRouter();
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const key = computed(() => ({ missionId: missionId.value, revisionId: props.revision.id }));
const rollout = useRemoteQuery(key, fetchRollout);
useMissionInvalidation(missionId, ["catalog", "spacecraft"], rollout.refetch);
const mode = ref<"profiles" | "spacecraft" | null>(null);
const chosen = ref<readonly Readonly<{ id: string; allVersions: boolean }>[]>([]);
const canary = ref<readonly string[]>([]);
const acknowledged = ref(false);
const choice = computed((): RolloutChoice | null => {
  if (mode.value === "profiles" && chosen.value.length > 0)
    return { kind: "profiles", profiles: chosen.value };
  if (mode.value === "spacecraft" && canary.value.length > 0)
    return {
      kind: "spacecraft",
      ids: canary.value,
      reason: `Canary for rev ${props.revision.number}`,
    };
  return null;
});
const ops = computed(() => (choice.value ? rolloutOps(props.revision.id, choice.value) : []));
const dryRun = useRolloutDryRun(missionId, ops);

const profileOf = (id: string) =>
  rollout.state.value.status === "ready"
    ? (rollout.state.value.value.profiles.find((p) => p.id === id) ?? null)
    : null;
/** U25 (#308): a profile with no name reads "Unknown profile", never its id. */
const names = computed(() => chosen.value.map((c) => profileOf(c.id)?.name ?? "Unknown profile"));
/** One chosen profile: the catalog its older-version spacecraft keep ("rev 14"). */
const from = computed(() =>
  chosen.value.length === 1
    ? (profileOf(chosen.value[0]?.id ?? "")?.current_revision?.label ?? null)
    : null,
);
const unprofiled = computed(() =>
  mode.value === "profiles" && rollout.state.value.status === "ready"
    ? rollout.state.value.value.unprofiled_count
    : 0,
);
const label = computed(() =>
  choice.value
    ? stageLabel(props.revision.number, choice.value, names.value)
    : `Stage rev ${props.revision.number}`,
);
const blocked = computed((): string | null => {
  if (!choice.value) return "Choose profiles or spacecraft first.";
  const d = dryRun.value;
  if (d.status !== "ready") return d.status === "failed" ? d.text : "Waiting for the dry run.";
  if (d.noGo) return `NO-GO: ${d.noGo}`;
  // qa #50: a set that moves nobody isn't worth staging.
  if (rolloutMoves(d.preview, props.revision.id) === 0)
    return `Nothing to stage: no spacecraft would move to rev ${props.revision.number}.`;
  if (breakingLine.value && !acknowledged.value) return breakingLine.value.reason;
  return null;
});

const busy = ref(false);
const failure = ref<FailureOutcome | null>(null);
async function stage() {
  if (blocked.value !== null || busy.value) return;
  busy.value = true;
  failure.value = null;
  try {
    const breaking = breakingCount.value > 0 ? ` · ${breakingCount.value} breaking` : "";
    const r = await stageChange(missionId.value, {
      summary: `${label.value.replace(/^Stage /, "Roll out ")}${breaking}`,
      source: { surface: "catalog_rollout" },
      ops: ops.value,
    });
    if (!r.ok) return void (failure.value = failureOutcome(r.error, "staged"));
    refreshConfigState(missionId.value);
    await router.push({ name: "setup.changes" });
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel index="C3" title="Roll out to">
    <div class="flex flex-col gap-3">
      <RolloutChoose
        v-model:mode="mode"
        v-model:chosen="chosen"
        v-model:canary="canary"
        :mission-id="missionId"
        :revision-number="revision.number"
        :rollout="rollout.state.value"
        @retry="rollout.refetch"
      />
      <RolloutDryRun :dry-run="dryRun" :revision="revision" :from="from" :unprofiled="unprofiled" />
      <RolloutBreaking
        v-if="breakingLine"
        v-model="acknowledged"
        :breaking="breaking"
        :words="breakingLine"
      />
      <FailureOutcomeCallout v-if="failure" :outcome="failure" />
      <ApButton
        variant="primary"
        :disabled="busy || blocked !== null"
        :disabled-reason="blocked ?? 'Staging…'"
        @click="stage"
        >{{ label }}</ApButton
      >
      <p class="m-0 text-sm text-text-3">
        Everything in this change set applies as one generation, with one compatibility check.
      </p>
    </div>
  </ApPanel>
</template>
