<script setup lang="ts">
import { computed, reactive, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useRemoteQuery } from "@/api";
import { canAdministerOrganization, useMissionScope, useSession } from "@/shell";
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
const route = useRoute();
const router = useRouter();
const scope = useMissionScope();
const missionId = scope.value.mission.id;
const canManage = canAdministerOrganization(useSession(), scope.value.organization);
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
  if (value && draft.scidStart === "") draft.scidStart = String(nextFreeScid(value.spacecraft));
});

const empty: SpacecraftDirectory = { spacecraft: [] };
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
    <header class="flex flex-wrap items-center gap-4 border-b border-hairline pb-3">
      <RouterLink
        :to="{ name: 'setup.spacecraft' }"
        aria-label="Close and keep draft"
        class="inline-flex size-11 items-center justify-center border border-line text-text-3 no-underline hover:text-readout"
        >×</RouterLink
      >
      <div class="flex flex-col gap-0.5">
        <span class="font-mono text-xs text-text-4 uppercase"
          >Setup · {{ scope.mission.name }} · spacecraft</span
        >
        <h1 class="m-0 font-display text-xl font-semibold tracking-head uppercase">
          Add spacecraft
        </h1>
      </div>
      <ApStepBar
        class="min-w-[min(100%,560px)] flex-1"
        :steps="steps.map((s) => stepLabels[s])"
        :current="steps.indexOf(step)"
        label="Steps"
      />
    </header>
    <ApCallout v-if="!canManage" tone="off">
      Only an organization admin can add spacecraft. You can prepare a batch here, but not create
      it.
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
