<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useConsoleScope } from "@/shell";
import { ApBreadcrumb, ApEmptyState, ApPageHeader, ApRemote } from "@/ui";
import InvitationPanel from "./InvitationPanel.vue";
import { fetchPeople } from "./api.ts";

/** People.md Invitations: the email link's page (one h1 per page, qa #36). */
const scope = useConsoleScope();
const route = useRoute();
const org = computed(() =>
  scope.value.kind === "organization" || scope.value.kind === "mission"
    ? scope.value.organization
    : null,
);
const id = computed(() => String(route.params["invitationId"] ?? ""));
const { state, refetch } = useRemoteQuery(() => org.value?.id ?? null, fetchPeople);
const invitation = computed(() =>
  state.value.status === "ready"
    ? (state.value.value.invitations.find((i) => i.id === id.value) ?? null)
    : null,
);
const canManage = computed(
  () =>
    state.value.status === "ready" && state.value.value.permissions.includes("org.manage_members"),
);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[900px] flex-col gap-4">
    <ApBreadcrumb
      :crumbs="[
        { label: 'People & access', to: { name: 'org.people' } },
        { label: invitation?.email ?? 'Invitation', literal: true },
      ]"
    />
    <ApRemote :state="state" loading-label="Loading invitation…" @retry="refetch">
      <ApEmptyState
        v-if="!invitation"
        state="off"
        headline="This invitation isn't pending"
        sentence="It was accepted, revoked or replaced by a resend. Open People & access for the current list."
      />
      <template v-else>
        <ApPageHeader label="Invitation" :title="invitation.email" size="reading" />
        <InvitationPanel
          v-if="org"
          :org-id="org.id"
          :invitation="invitation"
          :can-manage="canManage"
          @changed="refetch"
        />
      </template>
    </ApRemote>
  </div>
</template>
