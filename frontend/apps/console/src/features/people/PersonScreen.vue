<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useConsoleScope, useSession } from "@/shell";
import { ApBreadcrumb, ApEmptyState, ApPageHeader, ApRemote, ApTag, type ApCrumb } from "@/ui";
import PersonAccess from "./PersonAccess.vue";
import PersonActivity from "./PersonActivity.vue";
import PersonManage from "./PersonManage.vue";
import { fetchPeople, roleLabel } from "./api.ts";

/** People.md person page: Access (capabilities in words), Activity, Manage (org admins). */
const scope = useConsoleScope();
const session = useSession();
const route = useRoute("org.people.person");
const org = computed(() =>
  scope.value.kind === "organization" || scope.value.kind === "mission"
    ? scope.value.organization
    : null,
);
const userId = computed(() => String(route.params.userId ?? ""));
const { state, refetch } = useRemoteQuery(() => org.value?.id ?? null, fetchPeople);
const member = computed(() =>
  state.value.status === "ready"
    ? (state.value.value.members.find((m) => m.user_id === userId.value) ?? null)
    : null,
);
const canManage = computed(
  () =>
    state.value.status === "ready" && state.value.value.permissions.includes("org.manage_members"),
);
const crumbs = computed((): readonly ApCrumb[] => [
  { label: "People & access", to: { name: "org.people" } },
  { label: member.value?.display_name ?? member.value?.email ?? userId.value, literal: true },
]);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1100px] flex-col gap-4">
    <ApBreadcrumb :crumbs="crumbs" />
    <ApRemote :state="state" loading-label="Loading person…" @retry="refetch">
      <ApEmptyState
        v-if="!member"
        state="off"
        headline="Not a member of this organization"
        sentence="They may have been removed. Open People & access for the current list."
      />
      <template v-else>
        <ApPageHeader
          :label="org?.name ?? ''"
          :title="member.display_name ?? member.email"
          size="reading"
        >
          <template #subtitle>
            <span class="flex items-center gap-3">
              <ApTag state="off" :label="roleLabel(member.role)" />
              <span class="font-mono text-sm text-text-3">{{ member.email }}</span>
            </span>
          </template>
        </ApPageHeader>
        <PersonAccess :capabilities="member.capabilities" />
        <!-- The person's activity is the org audit log: org admins only (qa §6). -->
        <PersonActivity
          v-if="org && canManage"
          :org-id="org.id"
          :user-id="member.user_id"
          :name="member.display_name ?? member.email"
        />
        <PersonManage
          v-if="org && canManage"
          :org-id="org.id"
          :member="member"
          :self="member.user_id === session.user.id"
          @changed="refetch"
        />
      </template>
    </ApRemote>
  </div>
</template>
