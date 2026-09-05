<script setup lang="ts">
import type { FullPageSurfaceProps } from "@cadence/plugin-sdk";
import { CButton, CStatePanel } from "@cadence/ui";
import { computed, onMounted, ref, shallowRef } from "vue";
import type { Component } from "vue";
import type { OrganizationAdminSurface } from "./organization-admin-contract";
import { SURFACE_CONTRACTS } from "./organization-admin-contract";
import { surfaceComponents } from "./surface-components";

type SurfacePayload = Record<string, unknown>;

const props = defineProps<FullPageSurfaceProps>();
const presentation = shallowRef<SurfacePayload>();
const loading = ref(true);
const error = ref<string>();
const actionPending = ref(false);
const actionNotice = ref<string>();
let loadGeneration = 0;

const surfaceId = computed(() => props.surface.surfaceId as OrganizationAdminSurface);
const surface = computed(() =>
  SURFACE_CONTRACTS.find((candidate) => candidate.surfaceId === surfaceId.value),
);
const renderer = computed<Component | null>(
  () => (surfaceComponents[surfaceId.value] as Component | undefined) ?? null,
);
const rendererName = computed(() => surface.value?.component ?? "Unavailable");

const actionEvents: Record<OrganizationAdminSurface, Record<string, string>> = {
  organization_home: {},
  provider_accounts: {},
  provider_account_new: {
    validate: "validate_provider_account_form",
    save: "register_provider_account",
  },
  provider_account_show: {
    "validate-account": "validate_provider_account",
    "rotate-credential": "rotate_provider_credential",
    "revoke-credential": "revoke_provider_credential",
    "grant-mission": "grant_provider_account_mission",
    "revoke-grant": "revoke_provider_account_mission",
  },
  notifications: {
    "accept-invitation": "accept_invitation",
    "mark-read": "mark_notification_read",
  },
  notifications_bell: {
    "mark-read": "mark_notification_read",
  },
  admin_home: {},
  admin_runtime: {
    refresh: "refresh_runtime",
    filter_decisions: "filter_runtime_decisions",
  },
  admin_organizations: {},
  admin_organization_new: {
    validate: "validate_organization",
    save: "create_organization",
  },
  admin_organization_show: {
    "issue-service-identity": "issue_service_identity",
    "dismiss-service-token": "dismiss_service_token",
  },
  admin_organization_invite: {
    validate: "validate_invitation",
    save: "invite_organization_member",
  },
};

const actionListeners = computed(() =>
  Object.fromEntries(
    Object.entries(actionEvents[surfaceId.value] ?? {}).map(([eventName, actionId]) => [
      eventName,
      (input: unknown) => void executeAction(actionId, input),
    ]),
  ),
);

onMounted(() => void loadSurface());

async function loadSurface(): Promise<void> {
  const generation = ++loadGeneration;
  loading.value = true;
  error.value = undefined;
  presentation.value = undefined;

  try {
    if (!surface.value || !renderer.value) throw new Error("The selected surface is unavailable.");

    const response = await props.bridge.query<unknown>({
      queryId: props.surface.dataContract.id,
      version: props.surface.dataContract.version,
      context: props.context,
    });
    if (generation !== loadGeneration) return;
    presentation.value = unwrapSurfaceResponse(response, props.surface.dataContract.version);
  } catch (reason) {
    if (generation !== loadGeneration) return;
    error.value = reason instanceof Error ? reason.message : "The organization surface failed.";
  } finally {
    if (generation === loadGeneration) loading.value = false;
  }
}

async function executeAction(actionId: string, input: unknown): Promise<void> {
  if (actionPending.value) return;
  if (!props.surface.actions.includes(actionId)) {
    error.value = `Phoenix did not declare ${actionId} for ${props.surface.surfaceId}.`;
    return;
  }

  actionPending.value = true;
  actionNotice.value = undefined;
  error.value = undefined;

  try {
    const receipt = await props.bridge.execute<Record<string, unknown>, Record<string, unknown>>({
      applicationKey: props.application.applicationKey,
      applicationVersion: props.application.applicationVersion,
      actionId,
      input: isRecord(input) ? input : {},
      context: props.context,
    });
    actionNotice.value = `Phoenix accepted ${actionId}.`;
    const result = receipt.result;

    if (isRecord(result) && typeof result.navigate === "string") {
      window.location.assign(result.navigate);
    } else if (isRecord(result) && isRecord(result.patch)) {
      presentation.value = {
        ...(presentation.value ?? {}),
        ...result.patch,
      };
    } else {
      await loadSurface();
    }
  } catch (reason) {
    error.value = reason instanceof Error ? reason.message : "The organization action failed.";
  } finally {
    actionPending.value = false;
  }
}

function unwrapSurfaceResponse(value: unknown, expectedVersion: number): SurfacePayload {
  if (!isRecord(value)) throw new Error("The organization surface response is invalid.");

  if ("queryVersion" in value && value.queryVersion !== expectedVersion) {
    throw new Error("The organization surface response version is invalid.");
  }

  const payload = value.presentation ?? value.trusted_surface ?? value.data;
  if (payload !== undefined) {
    if (!isRecord(payload)) throw new Error("The organization surface presentation is invalid.");
    return payload;
  }

  return value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
</script>

<template>
  <div
    id="organization-admin-application"
    :data-organization-admin-surface="props.surface.surfaceId"
    :data-organization-admin-renderer="rendererName"
  >
    <CStatePanel
      v-if="loading"
      id="organization-admin-loading"
      title="Loading organization surface"
      description="Requesting the Phoenix-owned organization presentation."
      tone="loading"
      aria-live="polite"
    />
    <CStatePanel
      v-else-if="error"
      id="organization-admin-error"
      title="Organization surface unavailable"
      :description="error"
      tone="error"
      aria-live="assertive"
    >
      <template #action>
        <CButton id="retry-organization-admin" size="sm" @click="loadSurface">
          Retry query
        </CButton>
      </template>
    </CStatePanel>
    <template v-else-if="renderer && presentation">
      <aside v-if="actionPending" id="organization-admin-action-loading" role="status">
        Sending the organization action to Phoenix…
      </aside>
      <aside v-if="actionNotice" id="organization-admin-action-notice" role="status">
        {{ actionNotice }}
      </aside>
      <component :is="renderer" v-bind="presentation" v-on="actionListeners" />
    </template>
  </div>
</template>
