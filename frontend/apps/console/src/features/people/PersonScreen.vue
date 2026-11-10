<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useConsoleScope, useSession } from "@/shell";
import { ApBreadcrumb, ApEmptyState, ApPageHeader, ApPanel, ApRemote, ApTag } from "@/ui";
import PersonActivity from "./PersonActivity.vue";
import PersonManage from "./PersonManage.vue";
import { accessGroups } from "./admin.ts";
import { fetchPeople, roleLabel } from "./api.ts";

/** People.md person page: Access (capabilities in words), Activity, Manage (org admins). */
const scope = useConsoleScope();
const session = useSession();
const route = useRoute();
const org = computed(() =>
  scope.value.kind === "organization" || scope.value.kind === "mission"
    ? scope.value.organization
    : null,
);
const userId = computed(() => String(route.params["userId"] ?? ""));
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
const crumbs = computed(() => [
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
        <ApPanel index="P1" title="Access">
          <dl class="m-0 grid grid-cols-1 gap-x-8 gap-y-3 md:grid-cols-2">
            <div v-for="g in accessGroups(member.capabilities)" :key="g.group">
              <dt class="ap-label mb-1">{{ g.group }}</dt>
              <dd v-for="l in g.lines" :key="l.text" class="m-0 flex justify-between gap-4 text-md">
                <span class="text-text-2">{{ l.text }}</span>
                <span class="font-mono" :class="l.yes ? 'text-readout' : 'text-text-4'">{{
                  l.yes ? "YES" : "NO"
                }}</span>
              </dd>
            </div>
          </dl>
        </ApPanel>
        <PersonActivity v-if="org" :org-id="org.id" :user-id="member.user_id" />
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
