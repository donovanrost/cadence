<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useConsoleScope } from "@/shell";
import { ApBreadcrumb, ApEmptyState, ApPageHeader, ApRemote } from "@/ui";
import InvitationPanel from "./InvitationPanel.vue";
import { fetchPeople, type Invitation } from "./api.ts";

/** People.md Invitations: the email link's page (one h1 per page, qa #36). */
const scope = useConsoleScope();
const route = useRoute("org.people.invitation");
const org = computed(() =>
  scope.value.kind === "organization" || scope.value.kind === "mission"
    ? scope.value.organization
    : null,
);
const id = computed(() => String(route.params.invitationId ?? ""));
const { state, refetch } = useRemoteQuery(() => org.value?.id ?? null, fetchPeople);
const found = computed(() =>
  state.value.status === "ready"
    ? (state.value.value.invitations.find((i) => i.id === id.value) ?? null)
    : null,
);
// a11y A5: Resend moves the route to the new id before the list re-reads. Until the new row arrives,
// keep the panel on the old one, so its "Sent again" note and the focus on Resend survive.
const held = ref<{ to: string; row: Invitation } | null>(null);
const invitation = computed(
  () => found.value ?? (held.value?.to === id.value ? held.value.row : null),
);
function moving(to: string) {
  if (found.value) held.value = { to, row: found.value };
}
watch(found, (row) => {
  if (row && row.id === held.value?.to) held.value = null;
});
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
          @moving="moving"
          @changed="refetch"
        />
      </template>
    </ApRemote>
  </div>
</template>
