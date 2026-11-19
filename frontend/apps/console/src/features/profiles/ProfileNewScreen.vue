<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { fetchKindSchema } from "@/features/changes/index.ts";
import { useMissionScope } from "@/shell";
import { ApBreadcrumb, ApPageHeader, ApRemote, type ApCrumb } from "@/ui";
import { fetchProfileDetail } from "./detail.ts";
import { blankForm, duplicateForm } from "./newProfile.ts";
import ProfileNewForm from "./ProfileNewForm.vue";
import ProfileStartFrom from "./ProfileStartFrom.vue";

/** Profile.md `New profile` (`?from=<id>`: Duplicate as new profile, prefilled from it). */
const route = useRoute();
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const from = computed(() =>
  typeof route.query["from"] === "string" && route.query["from"] ? route.query["from"] : null,
);
const source = useRemoteQuery(
  () => (from.value ? { missionId: missionId.value, profileId: from.value } : null),
  fetchProfileDetail,
);
const schema = useRemoteQuery(
  () => (from.value ? null : { missionId: missionId.value, kind: "spacecraft_profile" as const }),
  fetchKindSchema,
);
/** Until the server serves a profile kind schema, a blank profile starts from an existing one. */
const noSchema = computed(
  () => schema.state.value.status === "failed" && schema.state.value.error.kind === "invalid",
);
const crumbs: readonly ApCrumb[] = [
  { label: "Profiles", to: { name: "setup.profiles" } },
  { label: "New profile" },
];
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1000px] flex-col gap-4">
    <ApBreadcrumb :crumbs="crumbs" />
    <ApPageHeader title="New profile" size="reading" />
    <ApRemote v-if="from" :state="source.state.value" loading-label="Loading profile…">
      <template #default="{ value }">
        <ProfileNewForm
          :key="value.profile.id"
          :mission-id="missionId"
          :form="duplicateForm(value)"
          :initial-name="`${value.profile.name} (copy)`"
          :copied-from="{ name: value.profile.name, version: value.profile.version }"
        />
      </template>
    </ApRemote>
    <ProfileStartFrom v-else-if="noSchema" :mission-id="missionId" />
    <ApRemote v-else :state="schema.state.value" loading-label="Loading fields…">
      <template #default="{ value }">
        <ProfileNewForm :mission-id="missionId" :form="blankForm(value)" initial-name="" />
      </template>
    </ApRemote>
  </div>
</template>
