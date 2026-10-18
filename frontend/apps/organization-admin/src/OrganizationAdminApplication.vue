<script setup lang="ts">
import {
  providerAccountActions,
  ProviderAccountRegistration,
  readRegistration,
  readAccountDirectory,
  RegistrationActionFailure,
  type RegistrationPort,
  ProviderAccountDetail,
  readAccountDetail,
  AccountActionFailure,
  type AccountDetailPort,
} from "@cadence/communications/provider-accounts";
import {
  createFederatedActionLifecycle,
  type FullPageSurfaceProps,
  type HostActionReceipt,
} from "@cadence/plugin-sdk";
import { computed, onBeforeUnmount, onErrorCaptured, ref, shallowRef, watch } from "vue";
import type { Component } from "vue";
import type { OrganizationAdminSurface } from "./organization-admin-contract";
import { SURFACE_CONTRACTS } from "./organization-admin-contract";
import { surfaceComponents } from "./surface-components";
import NotificationsBell from "./NotificationsBell.vue";

type SurfacePayload = Record<string, unknown>;

const props = defineProps<FullPageSurfaceProps>();
const presentation = shallowRef<SurfacePayload>();
const registration = shallowRef<ReturnType<typeof readRegistration>>();
const registrationPort = shallowRef<RegistrationPort>();
const accountDetail = shallowRef<ReturnType<typeof readAccountDetail>>();
const accountDetailPort = shallowRef<AccountDetailPort>();
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
  ...providerAccountActions,
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

function createActionLifecycle() {
  return createFederatedActionLifecycle({
    applicationKey: props.application.applicationKey,
    applicationVersion: props.application.applicationVersion,
    surfaceId: props.surface.surfaceId,
    surfaceVersion: props.surface.version,
    declaredActions: props.surface.actions,
    context: props.context,
    execute: props.bridge.execute,
    requery: loadSurface,
    navigate: (href) =>
      (props.bridge.navigate ?? ((target) => window.location.assign(target)))(href),
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
      actionError.value =
        reason instanceof Error ? reason.message : `The ${actionId} action failed.`;
    },
    onFinished: () => {
      actionPending.value = false;
    },
  });
}
let actionLifecycle = createActionLifecycle();

onBeforeUnmount(() => {
  ++loadGeneration;
  actionLifecycle.invalidate();
});
onErrorCaptured(() => {
  if (
    !["provider_accounts", "provider_account_new", "provider_account_show"].includes(
      props.surface.surfaceId,
    )
  )
    return;
  registration.value = undefined;
  accountDetail.value = undefined;
  error.value = "The provider account page could not be displayed.";
  return false;
});
watch(
  () => [
    props.context,
    props.context.organizationId,
    props.surface,
    props.bridge,
    props.application,
  ],
  () => {
    actionLifecycle.invalidate();
    actionLifecycle = createActionLifecycle();
    actionPending.value = false;
    actionError.value = undefined;
    actionNotice.value = undefined;
    actionReceipt.value = undefined;
    void loadSurface();
  },
  { immediate: true },
);

function scopedRegistrationPort(): RegistrationPort {
  const { context, surface, application, bridge } = props;
  return {
    async execute(action, input) {
      const actionId = providerAccountActions.provider_account_new[action];
      if (!surface.actions.includes(actionId)) throw new RegistrationActionFailure("rejected");
      try {
        return await bridge.execute({
          applicationKey: application.applicationKey,
          applicationVersion: application.applicationVersion,
          surfaceId: surface.surfaceId,
          surfaceVersion: surface.version,
          actionId,
          input,
          context,
        });
      } catch (reason) {
        const rejected =
          isRecord(reason) &&
          typeof reason.status === "number" &&
          reason.status >= 400 &&
          reason.status < 500 &&
          ["invalid_input", "invalid_scope", "forbidden", "unsupported_action"].includes(
            String(reason.code),
          );
        throw new RegistrationActionFailure(rejected ? "rejected" : "unknown");
      }
    },
    navigate(href) {
      (bridge.navigate ?? ((target) => window.location.assign(target)))(href);
    },
  };
}

async function loadSurface(): Promise<void> {
  const generation = ++loadGeneration;
  loading.value = true;
  error.value = undefined;
  presentation.value = undefined;
  registration.value = undefined;
  registrationPort.value = undefined;
  accountDetail.value = undefined;
  accountDetailPort.value = undefined;

  try {
    if (!surface.value || !renderer.value) throw new Error("The selected surface is unavailable.");
    if (
      props.surface.surfaceId === "provider_accounts" &&
      (props.context.scope !== "organization" ||
        !props.context.organizationId ||
        props.application.applicationKey !== "organization_admin" ||
        props.application.applicationVersion !== 1 ||
        props.surface.version !== 1 ||
        props.surface.dataContract.id !== "cadence.organization.provider_accounts.list" ||
        props.surface.dataContract.version !== 1)
    )
      throw new Error("Unsupported directory context.");
    if (
      props.surface.surfaceId === "provider_account_new" &&
      (props.context.scope !== "organization" ||
        !props.context.organizationId ||
        props.application.applicationKey !== "organization_admin" ||
        props.application.applicationVersion !== 1 ||
        props.surface.version !== 1 ||
        props.surface.dataContract.id !== "cadence.organization.provider_accounts.new" ||
        props.surface.dataContract.version !== 1)
    )
      throw new Error("Unsupported registration context.");
    if (
      props.surface.surfaceId === "provider_account_show" &&
      (props.context.scope !== "organization" ||
        !props.context.organizationId ||
        props.application.applicationKey !== "organization_admin" ||
        props.application.applicationVersion !== 1 ||
        props.surface.version !== 1 ||
        props.surface.dataContract.id !== "cadence.organization.provider_account.show" ||
        props.surface.dataContract.version !== 1)
    )
      throw new Error("Unsupported account context.");

    const response = await props.bridge.query<unknown>({
      queryId: props.surface.dataContract.id,
      version: props.surface.dataContract.version,
      context: props.context,
    });
    if (generation !== loadGeneration) return;
    const payload = unwrapSurfaceResponse(response, props.surface.dataContract.version);
    if (props.surface.surfaceId === "provider_account_new") {
      registration.value = readRegistration(payload, props.surface.dataContract.version);
      registrationPort.value = scopedRegistrationPort();
    } else if (
      props.surface.surfaceId === "provider_account_show" &&
      props.context.scope === "organization"
    ) {
      accountDetail.value = readAccountDetail(
        payload,
        props.context.organizationId,
        props.surface.dataContract.version,
      );
      accountDetailPort.value = scopedAccountDetailPort();
    } else if (props.surface.surfaceId === "provider_accounts") {
      if (props.context.scope !== "organization") throw new Error("Unsupported directory context.");
      presentation.value = readAccountDirectory(
        payload,
        props.context.organizationId,
        props.surface.dataContract.version,
      );
    } else presentation.value = payload;
  } catch (reason) {
    if (generation !== loadGeneration) return;
    error.value = ["provider_accounts", "provider_account_new", "provider_account_show"].includes(
      props.surface.surfaceId,
    )
      ? "The provider account page could not be loaded."
      : reason instanceof Error
        ? reason.message
        : "The organization surface failed.";
  } finally {
    if (generation === loadGeneration) loading.value = false;
  }
}

async function executeAction(actionId: string, input: unknown): Promise<void> {
  await actionLifecycle.execute(actionId, isRecord(input) ? input : {});
}

function scopedAccountDetailPort(): AccountDetailPort {
  const { surface, application, bridge } = props;
  const context = { ...props.context };
  return {
    async execute(action, input) {
      const actionId = providerAccountActions.provider_account_show[action];
      if (!surface.actions.includes(actionId)) throw new AccountActionFailure("rejected");
      try {
        return await bridge.execute({
          applicationKey: application.applicationKey,
          applicationVersion: application.applicationVersion,
          surfaceId: surface.surfaceId,
          surfaceVersion: surface.version,
          actionId,
          input,
          context,
        });
      } catch (reason) {
        const rejected =
          isRecord(reason) &&
          typeof reason.status === "number" &&
          reason.status >= 400 &&
          reason.status < 500 &&
          [
            "invalid_input",
            "invalid_scope",
            "forbidden",
            "unsupported_action",
            "stale_provider_account",
          ].includes(String(reason.code));
        throw new AccountActionFailure(rejected ? "rejected" : "unknown");
      }
    },
    async query() {
      return unwrapSurfaceResponse(
        await bridge.query({
          queryId: surface.dataContract.id,
          version: surface.dataContract.version,
          context,
        }),
        surface.dataContract.version,
      );
    },
  };
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
    <ProviderAccountRegistration
      v-else-if="registration && registrationPort && props.context.scope === 'organization'"
      :model="registration"
      :port="registrationPort"
      :organization-id="props.context.organizationId"
    />
    <ProviderAccountDetail
      v-else-if="accountDetail && accountDetailPort"
      :model="accountDetail"
      :port="accountDetailPort"
    />
    <NotificationsBell
      v-else-if="surfaceId === 'notifications_bell' && presentation"
      :context="presentation.context"
      :expected-user-id="props.context.scope === 'user' ? props.context.userId : undefined"
    />
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
