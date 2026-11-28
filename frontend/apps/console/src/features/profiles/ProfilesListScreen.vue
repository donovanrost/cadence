<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import { useCanStage } from "@/features/changes/index.ts";
import { ApButton, ApEmptyState, ApPageHeader, ApPanel, ApRemote, plural } from "@/ui";
import ProfilesTable from "./ProfilesTable.vue";
import { fetchProfiles } from "./api.ts";

/** Setup › Profiles (rail 03). Spec: docs/apogee/ux/screens/Profile.md § Profile list. */
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const { state, refetch } = useRemoteQuery(missionId, fetchProfiles);
useMissionInvalidation(missionId, ["spacecraft"], refetch);
/** Profile.md: read-only without config.stage (same gate as the profile editors). */
const canStage = useCanStage(scope.value.mission.id);

const title = computed(() =>
  state.value.status === "ready" ? plural(state.value.value.length, "profile") : "Profiles",
);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader :label="`${scope.mission.name} · profiles`" :title="title" size="reading">
      <template #subtitle>
        <span class="text-md text-text-3"
          >A profile holds the configuration a block of spacecraft shares.</span
        >
      </template>
      <ApButton v-if="canStage" variant="primary" :to="{ name: 'setup.profile.new' }"
        >New profile</ApButton
      >
    </ApPageHeader>
    <ApPanel index="A1" title="Profiles" flush>
      <ApRemote :state="state" loading-label="Loading profiles…" @retry="refetch">
        <template #default="{ value }">
          <ApEmptyState
            v-if="value.length === 0"
            state="off"
            headline="No profiles yet"
            sentence="A profile holds the configuration a block of spacecraft shares. Every spacecraft pins one."
          />
          <ProfilesTable v-else :rows="value" />
        </template>
      </ApRemote>
    </ApPanel>
  </div>
</template>
