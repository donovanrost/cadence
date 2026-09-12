<script setup lang="ts">
import { computed, onErrorCaptured, ref, watch } from "vue";
import PlatformOverviewPanel from "./features/platform-overview/PlatformOverviewPanel.vue";
import OrganizationDirectoryPanel from "./features/organization-directory/OrganizationDirectoryPanel.vue";
import OrganizationCreatePanel from "./features/organization-create/OrganizationCreatePanel.vue";
import { readPlatformOverview } from "./features/platform-overview/contracts";
import { readOrganizationDirectory } from "./features/organization-directory/contracts";
import { readOrganizationCreate } from "./features/organization-create/contracts";
import { record, identifier } from "./shared/platform-contract";
import OrganizationDetailPanel from "./features/organization-detail/OrganizationDetailPanel.vue";
import OrganizationInvitePanel from "./features/organization-invite/OrganizationInvitePanel.vue";
import { readOrganizationDetail } from "./features/organization-detail/contracts";
import { readOrganizationInvite } from "./features/organization-invite/contracts";
const props = defineProps<{
  page: string;
  snapshot: unknown;
  userId: unknown;
  organizationId?: unknown;
  csrfToken?: string;
  act: (event: string, input: Record<string, unknown>) => Promise<unknown>;
  refresh: () => Promise<void>;
}>();
const crashed = ref(false);
watch(
  () => [props.snapshot, props.userId, props.page, props.organizationId],
  () => {
    crashed.value = false;
  },
);
onErrorCaptured(() => {
  crashed.value = true;
  return false;
});
const admitted = computed(() => {
  const value = props.snapshot;
  if (
    !record(value) ||
    value.version !== 1 ||
    value.status !== "ready" ||
    value.page !== props.page ||
    value.user_id !== props.userId ||
    !identifier(value.action_token)
  )
    return null;
  try {
    switch (props.page) {
      case "platform_overview":
        return { page: props.page, model: readPlatformOverview(value.data, props.userId) } as const;
      case "organization_directory":
        return {
          page: props.page,
          model: readOrganizationDirectory(value.data, props.userId),
        } as const;
      case "organization_create":
        return {
          page: props.page,
          model: readOrganizationCreate(value.data, props.userId),
        } as const;
      case "organization_detail":
        if (value.organization_id !== props.organizationId) return null;
        return {
          page: props.page,
          model: readOrganizationDetail(value.data, props.userId, props.organizationId),
        } as const;
      case "organization_invite":
        if (value.organization_id !== props.organizationId) return null;
        return {
          page: props.page,
          model: readOrganizationInvite(value.data, props.userId, props.organizationId),
        } as const;
      default:
        return null;
    }
  } catch {
    return null;
  }
});
</script>
<template>
  <section id="core-platform-administration-page">
    <div
      v-if="crashed || !admitted"
      id="core-platform-administration-error"
      role="alert"
      class="card border border-warning/40 bg-base-200 p-6 space-y-4"
    >
      <p>This administration page is unavailable.</p>
      <button
        id="core-platform-administration-retry"
        type="button"
        class="btn btn-sm"
        @click="refresh"
      >
        Retry
      </button>
      <a href="/admin/organizations" class="link">Open the organization directory</a>
    </div>
    <PlatformOverviewPanel
      v-else-if="admitted.page === 'platform_overview'"
      :model="admitted.model"
    />
    <OrganizationDirectoryPanel
      v-else-if="admitted.page === 'organization_directory'"
      :model="admitted.model"
    />
    <OrganizationCreatePanel
      v-else-if="admitted.page === 'organization_create'"
      :model="admitted.model"
      :act="act"
      :refresh="refresh"
    />
    <OrganizationDetailPanel
      v-else-if="admitted.page === 'organization_detail'"
      :model="admitted.model"
      :csrf-token="csrfToken ?? ''"
      :act="act"
      :refresh="refresh"
    />
    <OrganizationInvitePanel
      v-else-if="admitted.page === 'organization_invite'"
      :model="admitted.model"
      :act="act"
      :refresh="refresh"
    />
  </section>
</template>
