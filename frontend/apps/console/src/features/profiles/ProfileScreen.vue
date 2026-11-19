<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute, type RouteLocationRaw } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { canAdministerOrganization, useMissionScope, useSession } from "@/shell";
import {
  ApBreadcrumb,
  ApButton,
  ApPageHeader,
  ApRemote,
  ApTabLinks,
  type ApCrumb,
  type ApTabLink,
} from "@/ui";
import LimitsNotice from "./LimitsNotice.vue";
import ProfileHistoryPanel from "./ProfileHistoryPanel.vue";
import ProfileRoutingPanel from "./ProfileRoutingPanel.vue";
import ProfileSectionView from "./ProfileSectionView.vue";
import { fetchProfileDetail, type ProfileDetail } from "./detail.ts";
import { profileSubline } from "./present.ts";
import { useFramingOff } from "./useFramingOff.ts";
import { useStagedFields } from "./staged.ts";

/** S4 · Profile. Spec: docs/apogee/ux/screens/Profile.md. */
const route = useRoute("setup.profile");
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

const session = useSession();
/** Profile.md: read-only without config.stage; same gate as the routing editor. */
const canStage = computed(() => canAdministerOrganization(session, scope.value.organization));
const editing = ref<string | null>(null);
const sectionParam = computed(() =>
  typeof route.params.section === "string" ? route.params.section : null,
);
function links(detail: ProfileDetail): readonly ApTabLink[] {
  const to = (section: string): RouteLocationRaw => ({
    name: "setup.profile",
    params: { profileId: detail.profile.id, section },
  });
  return [
    ...detail.sections.map((s) => ({ key: s.key, label: s.label, to: to(s.key) })),
    { key: "routing", label: "Routing", to: to("routing") },
    { key: "limits", label: "Limits", to: to("limits") },
    { key: "overrides", label: "Overrides", to: to("overrides"), count: detail.override_count },
    { key: "history", label: "History", to: to("history") },
  ];
}
const active = (detail: ProfileDetail) =>
  sectionParam.value ?? detail.sections[0]?.key ?? "routing";
const framingOff = useFramingOff(
  computed(() => scope.value.mission.id),
  computed(() => (state.value.status === "ready" ? active(state.value.value) : null)),
);
const staged = useStagedFields(
  computed(() => scope.value.mission.id),
  computed(() => profileId.value ?? ""),
);
const title = computed(() =>
  state.value.status === "ready" ? state.value.value.profile.name : "Profile",
);
const crumbs = computed((): readonly ApCrumb[] => [
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
      <ApButton
        v-if="canStage && profileId"
        :to="{ name: 'setup.profile.new', query: { from: profileId } }"
        >Duplicate as new profile</ApButton
      >
    </ApPageHeader>
    <ApRemote :state="state" loading-label="Loading profile…" @retry="refetch">
      <template #default="{ value }">
        <ApTabLinks :links="links(value)" :active="active(value)" label="Profile sections" />
        <ProfileHistoryPanel v-if="active(value) === 'history'" :detail="value" />
        <LimitsNotice v-else-if="active(value) === 'limits'" />
        <ProfileRoutingPanel
          v-else-if="active(value) === 'routing' || active(value) === 'overrides'"
          :detail="value"
          :part="active(value) === 'routing' ? 'routing' : 'overrides'"
        />
        <template v-else>
          <ProfileSectionView
            v-for="section in value.sections.filter((s) => s.key === active(value))"
            :key="section.key"
            v-model:editing="editing"
            :mission-id="scope.mission.id"
            :detail="value"
            :section="section"
            :can-stage="canStage"
            :framing-off="framingOff"
            :staged="staged"
          />
        </template>
      </template>
    </ApRemote>
  </div>
</template>
