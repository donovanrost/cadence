<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useConsoleScope } from "@/shell";
import { ApEmptyState, ApPageHeader, ApPanel, ApRemote, ApSegmented, plural } from "@/ui";
import CommandPoliciesPanel from "./CommandPoliciesPanel.vue";
import InvitationsTable from "./InvitationsTable.vue";
import InvitePanel from "./InvitePanel.vue";
import PeoplePanel from "./PeoplePanel.vue";
import ServiceIdentitiesPanel from "./ServiceIdentitiesPanel.vue";
import { fetchPeople, type People } from "./api.ts";

/** S5 · People & access (org-scoped). Spec: docs/apogee/ux/screens/People.md. */
const scope = useConsoleScope();
const organization = computed(() =>
  scope.value.kind === "organization" || scope.value.kind === "mission"
    ? scope.value.organization
    : null,
);
const { state, refetch } = useRemoteQuery(() => organization.value?.id ?? null, fetchPeople);
/** `?tab=` opens a section directly (service identity pages link back to it). */
const route = useRoute();
const initialTab = route.query["tab"];
const tab = ref<"people" | "invitations" | "services" | "policies">(
  initialTab === "invitations" || initialTab === "services" || initialTab === "policies"
    ? initialTab
    : "people",
);
const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
const subline = (p: People) =>
  [
    plural(p.members.length, "person", "people"),
    plural(p.invitations.filter((i) => i.status === "pending").length, "pending invite"),
  ].join(" · ");
/** Org admins only (O3 is 403 for members), even when ?tab=services is in the URL (qa §6). */
const admins = (p: People) => p.permissions.includes("org.manage_members");
const tabs = (p: People) => [
  { value: "people" as const, label: "People", count: p.members.length },
  { value: "invitations" as const, label: "Invitations", count: p.invitations.length },
  // Org admins only (O3 is 403 for members): gate on the caller's org permissions.
  ...(admins(p) ? [{ value: "services" as const, label: "Service identities" }] : []),
  { value: "policies" as const, label: "Command policies" },
];
/** U2 Invite beside People and Invitations only (ux §7 #9), with org.invite. */
const canInvite = (p: People) =>
  p.permissions.includes("org.invite") && (tab.value === "people" || tab.value === "invitations");
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader
      :label="`${organization?.name ?? ''} · organization`"
      title="People & access"
      size="reading"
    >
      <template v-if="state.status === 'ready'" #subtitle
        ><span class="text-md text-text-3">{{ subline(state.value) }}</span></template
      >
    </ApPageHeader>
    <ApPanel v-if="notProvided" index="U1" title="People" flush>
      <ApEmptyState
        state="off"
        headline="People not available in the console yet"
        sentence="This server doesn't serve organization members to the console yet."
      />
    </ApPanel>
    <ApRemote v-else :state="state" loading-label="Loading people…" @retry="refetch">
      <template #default="{ value }">
        <ApSegmented v-model="tab" :options="tabs(value)" label="Access sections" variant="tabs" />
        <div class="flex flex-wrap items-start gap-4">
          <div class="min-w-0 flex-[999_1_560px]">
            <PeoplePanel v-if="tab === 'people'" :members="value.members" />
            <CommandPoliciesPanel
              v-else-if="tab === 'policies' && organization"
              :organization="organization"
            />
            <ServiceIdentitiesPanel
              v-else-if="tab === 'services' && organization && admins(value)"
              :organization-id="organization.id"
            />
            <ApPanel v-else index="U1" title="Invitations" flush>
              <ApEmptyState v-if="value.invitations.length === 0" headline="No invitations" />
              <InvitationsTable v-else :rows="value.invitations" />
            </ApPanel>
          </div>
          <InvitePanel
            v-if="organization && canInvite(value)"
            :organization-id="organization.id"
            class="min-w-0 flex-[1_1_340px]"
            @invited="refetch"
          />
        </div>
      </template>
    </ApRemote>
  </div>
</template>
