<script setup lang="ts">
import { computed, reactive, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useRemoteQuery } from "@/api";
import { TakeoverHeader, useMissionScope } from "@/shell";
import { useConfigState } from "@/features/changes/index.ts";
import { ApCallout, ApRemote, ApStepBar } from "@/ui";
import { fetchProfiles, type ProfileSummary } from "@/features/profiles/index.ts";
import { fetchSpacecraftDirectory, type SpacecraftDirectory } from "../api.ts";
import { nextFreeScid } from "./batch.ts";
import { provideDraft, stepLabels, steps, type Step } from "./context.ts";
import { emptyDraft, loadDraft, propose, saveDraft, type Draft } from "./draft.ts";
import StepIdentity from "./StepIdentity.vue";
import StepOrbit from "./StepOrbit.vue";
import StepReview from "./StepReview.vue";
import StepSource from "./StepSource.vue";
import SummaryAside from "./SummaryAside.vue";

/** S2 · Add spacecraft (takeover, U5). Spec: docs/apogee/ux/screens/AddSpacecraft.md. */
const route = useRoute("setup.spacecraft.new");
const router = useRouter();
const scope = useMissionScope();
const missionId = scope.value.mission.id;
/**
 * #1160: adding spacecraft stages a change (config.stage, any mission operator). The callout waits
 * for the config state, so nobody is told they can't while it's still being read.
 */
const config = useConfigState(missionId);
const canManage = computed(
  () =>
    config.state.value.status === "ready" &&
    config.state.value.value.permissions.has("config.stage"),
);
const cannotStage = computed(() => config.state.value.status === "ready" && !canManage.value);
const { state, refetch } = useRemoteQuery(() => scope.value.mission.id, fetchSpacecraftDirectory);
const profilesQuery = useRemoteQuery(() => scope.value.mission.id, fetchProfiles);
const profiles = computed((): readonly ProfileSummary[] =>
  profilesQuery.state.value.status === "ready" ? profilesQuery.state.value.value : [],
);

const draft = reactive<Draft>(
  loadDraft(missionId) ?? emptyDraft(`${scope.value.mission.name.toUpperCase()}-{scid}`),
);
watch(draft, (value) => saveDraft(missionId, value), { deep: true });

const directory = computed(() => (state.value.status === "ready" ? state.value.value : null));
watch(directory, (value) => {
  if (!value || draft.scidStart !== "") return;
  const next = nextFreeScid(value.spacecraft, value.scids);
  if (next !== null) draft.scidStart = String(next);
});
// S9 (#313): the SCIDs in use are read when the screen opens, not refetched live: a failed
// background read would replace the wizard mid-edit. The server's stage-time check is the guard.

// One profile: preselect it so step 01 isn't a formality (still visible and changeable).
watch(profiles, (list) => {
  const only = list.length === 1 ? list[0] : undefined;
  if (only && draft.profileId === "") draft.profileId = only.id;
});

const empty: SpacecraftDirectory = { spacecraft: [], telemetry: "ok", scids: null };
const proposal = computed(() => propose(draft, directory.value ?? empty, profiles.value));
provideDraft({
  draft,
  set: (key, value) => {
    draft[key] = value;
  },
  directory: () => directory.value ?? empty,
  profiles: () => profiles.value,
  proposal: () => proposal.value,
});

const step = computed((): Step => {
  const param = route.params.step;
  return steps.find((s) => s === param) ?? "source";
});
function go(next: Step) {
  void router.push({ name: "setup.spacecraft.new", params: { step: next } }).catch(() => undefined);
}
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <TakeoverHeader
      title="Add spacecraft"
      context="Setup · spacecraft"
      :close="{ name: 'setup.spacecraft' }"
      close-label="Close and keep draft"
      title-as="h1"
    >
      <template #steps>
        <ApStepBar
          class="min-w-[min(100%,560px)] self-center px-3"
          :steps="steps.map((s) => stepLabels[s])"
          :current="steps.indexOf(step)"
          label="Steps"
        />
      </template>
    </TakeoverHeader>
    <ApCallout v-if="cannotStage" tone="off">
      Only mission operators can add spacecraft. You can prepare a batch here, but not create it.
    </ApCallout>
    <ApRemote :state="state" loading-label="Loading this mission's spacecraft…" @retry="refetch">
      <ApRemote
        :state="profilesQuery.state.value"
        loading-label="Loading profiles…"
        @retry="profilesQuery.refetch"
      >
        <div class="flex flex-wrap items-start gap-4">
          <div class="flex min-w-0 flex-[999_1_640px] flex-col gap-4">
            <StepSource v-if="step === 'source'" />
            <StepIdentity v-else-if="step === 'identity'" />
            <StepOrbit v-else-if="step === 'orbit'" />
            <StepReview v-else />
          </div>
          <SummaryAside
            :step="step"
            :can-manage="canManage"
            class="sticky top-0 min-w-0 flex-[1_1_340px]"
            @go="go"
          />
        </div>
      </ApRemote>
    </ApRemote>
  </div>
</template>
