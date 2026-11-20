<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute, type RouteLocationRaw } from "vue-router";
import { useRemoteQuery } from "@/api";
import { ApBreadcrumb, ApCallout, ApPageHeader, ApRemote, formatShort, outcomeRole } from "@/ui";
import { fetchOrganization } from "./api.ts";
import OrganizationInvite from "./OrganizationInvite.vue";
import OrganizationPanels from "./OrganizationPanels.vue";

/** Admin › one organization (Admin.md): members, invitations (Withdraw), missions; cross-org invite. */
const route = useRoute("admin.organization");
const orgId = computed(() => (typeof route.params.orgId === "string" ? route.params.orgId : ""));
const detail = useRemoteQuery(orgId, fetchOrganization);
const note = ref<{ tone: "nominal" | "caution" | "crit"; text: string } | null>(null);
const name = computed(() =>
  detail.state.value.status === "ready"
    ? detail.state.value.value.organization.name
    : "Organization",
);
const crumbs = computed((): readonly Readonly<{ label: string; to?: RouteLocationRaw }>[] => [
  { label: "Organizations", to: { name: "admin.organizations" } },
  { label: name.value },
]);
function changed(text: { tone: "nominal" | "caution" | "crit"; text: string }) {
  note.value = text;
  detail.refetch();
}
</script>

<template>
  <ApBreadcrumb :crumbs="crumbs" />
  <ApRemote
    :state="detail.state.value"
    loading-label="Loading organization…"
    @retry="detail.refetch"
  >
    <template #default="{ value }">
      <ApPageHeader
        :label="`Platform admin · ${value.organization.slug}`"
        :title="value.organization.name"
        size="reading"
      >
        <template v-if="value.organization.created_at" #subtitle
          ><span class="text-md text-text-3"
            >Created {{ formatShort(new Date(value.organization.created_at)) }}</span
          ></template
        >
        <OrganizationInvite
          :org-id="value.organization.id"
          :org-name="value.organization.name"
          @changed="changed"
        />
      </ApPageHeader>
      <ApCallout v-if="note" :tone="note.tone" :role="outcomeRole(note.tone)">{{
        note.text
      }}</ApCallout>
      <OrganizationPanels :detail="value" @changed="changed" />
      <p class="m-0 text-sm text-text-3">
        Changes to {{ value.organization.name }}'s members and invitations are recorded in its
        <RouterLink
          :to="{ name: 'org.audit', params: { org: value.organization.slug } }"
          class="text-readout hover:underline"
          >audit log</RouterLink
        >
        (Access).
      </p>
    </template>
  </ApRemote>
</template>
