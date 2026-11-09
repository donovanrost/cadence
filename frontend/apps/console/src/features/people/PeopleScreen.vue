<script setup lang="ts">
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api";
import { useConsoleScope } from "@/shell";
import {
  ApEmptyState,
  ApField,
  ApPageHeader,
  ApPanel,
  ApRemote,
  ApSegmented,
  formatCount,
  plural,
} from "@/ui";
import InvitationsTable from "./InvitationsTable.vue";
import InvitePanel from "./InvitePanel.vue";
import PeopleTable from "./PeopleTable.vue";
import ServiceIdentitiesPanel from "./ServiceIdentitiesPanel.vue";
import { fetchPeople, matchesPerson, type People } from "./api.ts";

/** S5 · People & access (org-scoped). Spec: docs/apogee/ux/screens/People.md. */
const scope = useConsoleScope();
const organization = computed(() =>
  scope.value.kind === "organization" || scope.value.kind === "mission"
    ? scope.value.organization
    : null,
);
const { state, refetch } = useRemoteQuery(() => organization.value?.id ?? null, fetchPeople);
const tab = ref<"people" | "invitations" | "services">("people");
const query = ref("");
const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
const subline = (p: People) =>
  [
    plural(p.members.length, "person", "people"),
    plural(p.invitations.filter((i) => i.status === "pending").length, "pending invite"),
  ].join(" · ");
const tabs = (p: People) => [
  { value: "people" as const, label: "People", count: p.members.length },
  { value: "invitations" as const, label: "Invitations", count: p.invitations.length },
  // Org admins only (O3 is 403 for members): gate on the caller's org permissions.
  ...(p.permissions.includes("org.manage_members")
    ? [{ value: "services" as const, label: "Service identities" }]
    : []),
];
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
          <ApPanel
            v-if="tab === 'people'"
            index="U1"
            title="People"
            class="min-w-0 flex-[999_1_560px]"
            flush
          >
            <template #header
              ><div class="w-[260px]">
                <ApField
                  v-model="query"
                  label="Filter people"
                  hidden-label
                  type="search"
                  placeholder="Filter by name, email or role"
                /></div
            ></template>
            <template #meta
              >{{ formatCount(value.members.filter((m) => matchesPerson(m, query)).length) }} of
              {{ formatCount(value.members.length) }}</template
            >
            <PeopleTable :rows="value.members.filter((m) => matchesPerson(m, query))" />
          </ApPanel>
          <ServiceIdentitiesPanel
            v-else-if="tab === 'services' && organization"
            :organization-id="organization.id"
            class="min-w-0 flex-[999_1_560px]"
          />
          <ApPanel v-else index="U1" title="Invitations" class="min-w-0 flex-[999_1_560px]" flush>
            <ApEmptyState v-if="value.invitations.length === 0" headline="No invitations" />
            <InvitationsTable v-else :rows="value.invitations" />
          </ApPanel>
          <InvitePanel
            v-if="organization && value.permissions.includes('org.invite')"
            :organization-id="organization.id"
            class="min-w-0 flex-[1_1_340px]"
            @invited="refetch"
          />
        </div>
      </template>
    </ApRemote>
  </div>
</template>
