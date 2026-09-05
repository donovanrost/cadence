<script setup lang="ts">
import { CStatePanel } from "@cadence/ui";
import { computed, type Component } from "vue";
import type { OrganizationAdminSurface } from "./organization-admin-contract";
import { exposedComponents } from "./surface-components";

const props = defineProps<{
  surface: OrganizationAdminSurface;
  payload?: Record<string, unknown>;
}>();

const component = computed<Component | null>(
  () => exposedComponents[componentName(props.surface)] ?? null,
);

function componentName(surface: OrganizationAdminSurface): keyof typeof exposedComponents {
  const contract = {
    organization_home: "OrganizationHome",
    provider_accounts: "ProviderAccountListPage",
    provider_account_new: "ProviderAccountNew",
    provider_account_show: "ProviderAccountShow",
    notifications: "NotificationsPage",
    notifications_bell: "NotificationsBell",
    admin_home: "AdminHome",
    admin_runtime: "AdminRuntime",
    admin_organizations: "AdminOrganizationListPage",
    admin_organization_new: "AdminOrganizationNew",
    admin_organization_show: "AdminOrganizationShow",
    admin_organization_invite: "AdminOrganizationInvite",
  } satisfies Record<OrganizationAdminSurface, keyof typeof exposedComponents>;

  return contract[surface];
}
</script>

<template>
  <div id="organization-admin-application" :data-organization-admin-surface="props.surface">
    <component v-if="component" :is="component" v-bind="props.payload ?? {}" />
    <CStatePanel
      v-else
      id="organization-admin-unsupported-surface"
      title="Surface unavailable"
      description="The requested organization administration surface is not available in this release."
      tone="error"
      aria-live="assertive"
    />
  </div>
</template>
