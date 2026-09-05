<script setup lang="ts">
import {
  createFederatedActionLifecycle,
  type FullPageSurfaceProps,
  type HostActionReceipt,
} from "@cadence/plugin-sdk";
import { computed, onBeforeUnmount, onMounted, ref, shallowRef } from "vue";
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
const actionError = ref<string>();
const actionNotice = ref<string>();
const actionReceipt = shallowRef<HostActionReceipt<unknown>>();
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

const actionLifecycle = createFederatedActionLifecycle({
  applicationKey: props.application.applicationKey,
  applicationVersion: props.application.applicationVersion,
  surfaceId: props.surface.surfaceId,
  surfaceVersion: props.surface.version,
  declaredActions: props.surface.actions,
  context: props.context,
  execute: props.bridge.execute,
  requery: loadSurface,
  navigate: (href) => window.location.assign(href),
  onStarted: () => {
    actionPending.value = true;
    actionError.value = undefined;
    actionNotice.value = undefined;
    actionReceipt.value = undefined;
  },
  onCompleted: (actionId, receipt) => {
    actionReceipt.value = receipt;
    actionNotice.value = `Phoenix completed ${actionId}.`;
  },
  onRejected: (actionId, reason) => {
    actionError.value = reason instanceof Error ? reason.message : `The ${actionId} action failed.`;
  },
  onFinished: () => {
    actionPending.value = false;
  },
});

onBeforeUnmount(() => actionLifecycle.invalidate());
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
  await actionLifecycle.execute(actionId, isRecord(input) ? input : {});
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
    <section
      v-if="loading"
      id="organization-admin-loading"
      class="flex min-h-80 flex-col items-center justify-center border border-base-300 bg-base-200 p-8 text-center"
      aria-live="polite"
    >
      <div role="status" aria-label="Loading organization surface">
        <p class="hud-label">Loading organization surface</p>
        <p class="mx-auto mt-2 max-w-md text-sm text-base-content/70">
          Requesting the Phoenix-owned organization presentation.
        </p>
      </div>
    </section>
    <section
      v-else-if="error"
      id="organization-admin-error"
      class="border border-error/40 bg-error/10 p-8 text-center"
      aria-live="assertive"
    >
      <p class="hud-label text-error">Organization surface unavailable</p>
      <p class="mx-auto mt-2 max-w-md text-sm text-base-content/70">{{ error }}</p>
      <div class="mt-5">
        <button
          id="retry-organization-admin"
          type="button"
          class="btn btn-primary btn-sm"
          @click="loadSurface"
        >
          Retry query
        </button>
      </div>
    </section>
    <template v-else-if="renderer && presentation">
      <aside
        v-if="actionPending"
        id="organization-admin-action-loading"
        role="status"
        aria-live="polite"
        class="border-l-2 border-info/60 bg-info/10 px-4 py-3 text-sm text-base-content/70"
      >
        Sending the organization action to Phoenix…
      </aside>
      <aside
        v-if="actionError"
        id="organization-admin-action-error"
        role="alert"
        aria-live="assertive"
        class="border-l-2 border-error/60 bg-error/10 px-4 py-3 text-sm text-base-content/70"
      >
        {{ actionError }}
      </aside>
      <aside
        v-if="actionNotice && actionReceipt"
        id="organization-admin-action-notice"
        role="status"
        aria-live="polite"
        :data-receipt-id="actionReceipt.receiptId"
        :data-completed-at="actionReceipt.completedAt"
        class="border-l-2 border-success/60 bg-success/10 px-4 py-3 text-sm text-base-content/70"
      >
        {{ actionNotice }} Receipt {{ actionReceipt.receiptId }} completed at
        {{ actionReceipt.completedAt }}.
      </aside>
      <component :is="renderer" v-bind="presentation" v-on="actionListeners" />
    </template>
  </div>
</template>
