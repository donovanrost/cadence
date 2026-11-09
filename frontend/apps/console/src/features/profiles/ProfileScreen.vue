<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import { ApBreadcrumb, ApPageHeader, ApRemote, ApTabLinks } from "@/ui";
import ProfileHistoryPanel from "./ProfileHistoryPanel.vue";
import ProfileRoutingPanel from "./ProfileRoutingPanel.vue";
import SchemaSectionPanel from "./SchemaSectionPanel.vue";
import { fetchProfileDetail, type ProfileDetail } from "./detail.ts";
import { profileSubline } from "./present.ts";

/** S4 · Profile (read-only until P2, DECISIONS #19). Spec: docs/apogee/ux/screens/Profile.md. */
const route = useRoute();
const scope = useMissionScope();
const profileId = computed(() =>
  typeof route.params.profileId === "string" ? route.params.profileId : null,
);
const key = computed(() =>
  profileId.value ? { missionId: scope.value.mission.id, profileId: profileId.value } : null,
);
const { state, refetch } = useRemoteQuery(key, fetchProfileDetail);
useMissionInvalidation(
  computed(() => scope.value.mission.id),
  ["spacecraft", "configuration"],
  refetch,
);

const sectionParam = computed(() =>
  typeof route.params.section === "string" ? route.params.section : null,
);
function links(detail: ProfileDetail) {
  const to = (section: string) => ({
    name: "setup.profile",
    params: { profileId: detail.profile.id, section },
  });
  return [
    ...detail.sections.map((s) => ({ key: s.key, label: s.label, to: to(s.key) })),
    { key: "routing", label: "Routing", to: to("routing") },
    { key: "overrides", label: "Overrides", to: to("overrides"), count: detail.override_count },
    { key: "history", label: "History", to: to("history") },
  ];
}
const active = (detail: ProfileDetail) =>
  sectionParam.value ?? detail.sections[0]?.key ?? "routing";
const title = computed(() =>
  state.value.status === "ready" ? state.value.value.profile.name : "Profile",
);
const crumbs = computed(() => [
  { label: "Profiles", to: { name: "setup.profiles" } },
  { label: title.value },
]);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApBreadcrumb :crumbs="crumbs" />
    <ApPageHeader :title="title" size="reading">
      <template v-if="state.status === 'ready'" #subtitle>
        <span class="text-md text-text-3">{{ profileSubline(state.value) }}</span>
      </template>
    </ApPageHeader>
    <ApRemote :state="state" loading-label="Loading profile…" @retry="refetch">
      <template #default="{ value }">
        <ApTabLinks :links="links(value)" :active="active(value)" label="Profile sections" />
        <ProfileHistoryPanel v-if="active(value) === 'history'" :detail="value" />
        <ProfileRoutingPanel
          v-else-if="active(value) === 'routing' || active(value) === 'overrides'"
          :detail="value"
          :part="active(value) === 'routing' ? 'routing' : 'overrides'"
        />
        <template v-else>
          <SchemaSectionPanel
            v-for="section in value.sections.filter((s) => s.key === active(value))"
            :key="section.key"
            :section="section"
            :inherit-count="value.inherit_count"
          />
        </template>
      </template>
    </ApRemote>
  </div>
</template>
