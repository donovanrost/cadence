<script setup lang="ts">
import type {
  FederatedApplicationProps,
  HostActionRequest,
  HostBridge,
  HostContext,
  HostQueryRequest,
} from "@cadence/plugin-sdk";
import { CButton, CStatePanel } from "@cadence/ui";
import { onMounted, ref, useAttrs } from "vue";
import ApplicationHost from "./ApplicationHost.vue";
import TelemetryDecomManage from "./TelemetryDecomManage.vue";

type ApplicationHostDto = {
  host: Record<string, unknown>;
  navigation: Record<string, unknown> | null;
  declarative_surface: Record<string, unknown> | null;
  application_surface_rows: Record<string, unknown>[];
  application_surface_activity: Record<string, unknown>[];
  application_surface_packet_groups: Record<string, unknown>[];
};

type ApplicationAction = {
  "action-id": string;
  application_action: Record<string, string | string[]>;
};

type HostAction = {
  applicationKey: "telemetry_decom";
  applicationVersion: 1;
  actionId: string;
  application_action: Record<string, string | string[]>;
  context: HostContext;
  idempotencyKey: string;
};

type TelemetryHost = {
  query<TResult>(request: HostQueryRequest): Promise<TResult>;
  action(request: HostAction): Promise<unknown>;
};

type TelemetryApplicationProps = {
  context: FederatedApplicationProps["context"];
  surface?: "manage" | "packet_bindings";
  pageProps?: Record<string, unknown>;
  host?: TelemetryHost;
  bridge?: HostBridge;
};

defineOptions({ inheritAttrs: false });
const props = defineProps<TelemetryApplicationProps>();
const attrs = useAttrs();
const host = props.host ?? (props.bridge ? legacyHost(props.bridge) : undefined);
const managedSurface = props.surface === "manage";

const presentation = ref<ApplicationHostDto>();
const loading = ref(true);
const error = ref<string>();
const actionPending = ref(false);
const actionError = ref<string>();
const actionNotice = ref<string>();
let loadGeneration = 0;

onMounted(() => {
  if (!managedSurface) loadApplication();
});

async function loadApplication(): Promise<boolean> {
  const generation = ++loadGeneration;
  loading.value = true;
  error.value = undefined;
  presentation.value = undefined;

  try {
    if (!host) throw new Error("The telemetry application host bridge is unavailable.");

    const response = await host.query<unknown>({
      queryId: "cadence.packet_bindings.manage",
      version: 1,
      context: props.context,
    });
    if (generation !== loadGeneration) return false;
    presentation.value = assertApplicationHostDto(response);
    return true;
  } catch (reason) {
    if (generation !== loadGeneration) return false;
    error.value = messageFor(reason, "The packet bindings host query failed.");
    return false;
  } finally {
    if (generation === loadGeneration) loading.value = false;
  }
}

async function retryQuery(): Promise<void> {
  actionError.value = undefined;
  actionNotice.value = undefined;
  await loadApplication();
}

async function submitApplicationAction(payload: ApplicationAction): Promise<void> {
  actionPending.value = true;
  actionError.value = undefined;
  actionNotice.value = undefined;

  try {
    if (!host) throw new Error("The telemetry application host bridge is unavailable.");

    await host.action({
      applicationKey: "telemetry_decom",
      applicationVersion: 1,
      actionId: payload["action-id"],
      application_action: payload.application_action,
      context: props.context,
      idempotencyKey: crypto.randomUUID(),
    });

    if (await loadApplication()) {
      actionNotice.value = "Action accepted and packet bindings refreshed from the host.";
    } else {
      actionError.value = "Action completed, but the refreshed packet bindings are unavailable.";
    }
  } catch (reason) {
    actionError.value = messageFor(reason, "The packet bindings action failed.");
  } finally {
    actionPending.value = false;
  }
}

function ignoreApplicationFormChange(): void {
  // This surface has no host-side form-change contract; only submitted packet actions are supported.
}

function ignoreApplicationTablePage(): void {
  // This surface has no paginated table contract; page events are intentionally ignored.
}

function assertApplicationHostDto(value: unknown): ApplicationHostDto {
  if (
    !isRecord(value) ||
    !isRecord(value.host) ||
    !("navigation" in value) ||
    !("declarative_surface" in value) ||
    !Array.isArray(value.application_surface_rows) ||
    !Array.isArray(value.application_surface_activity) ||
    !Array.isArray(value.application_surface_packet_groups)
  ) {
    throw new Error("The packet bindings query returned an invalid ApplicationHost DTO.");
  }

  if (value.navigation !== null && !isRecord(value.navigation)) {
    throw new Error("The packet bindings query returned an invalid navigation DTO.");
  }

  if (value.declarative_surface !== null && !isRecord(value.declarative_surface)) {
    throw new Error("The packet bindings query returned an invalid declarative surface DTO.");
  }

  return value as ApplicationHostDto;
}

function legacyHost(bridge: HostBridge): TelemetryHost {
  return {
    query: (request) => bridge.query(request),
    action: ({
      applicationKey,
      applicationVersion,
      actionId,
      application_action,
      context,
      idempotencyKey,
    }) => {
      const request: HostActionRequest<Record<string, string | string[]>> & {
        idempotencyKey: string;
      } = {
        applicationKey,
        applicationVersion,
        actionId,
        input: application_action,
        context,
        idempotencyKey,
      };

      return bridge.execute(request);
    },
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function messageFor(reason: unknown, fallback: string): string {
  return reason instanceof Error ? reason.message : fallback;
}
</script>

<template>
  <div id="telemetry-decom-application">
    <TelemetryDecomManage
      v-if="managedSurface"
      v-bind="props.pageProps ?? {}"
      v-bind="attrs"
    />
    <CStatePanel
      v-else-if="loading"
      id="telemetry-decom-loading"
      title="Loading packet bindings"
      :description="
        actionPending
          ? 'The host accepted the action. Refreshing the canonical packet-binding surface.'
          : 'Requesting the spacecraft packet-binding presentation from the Phoenix host.'
      "
      tone="loading"
      aria-live="polite"
    />

    <CStatePanel
      v-else-if="error"
      id="telemetry-decom-error"
      title="Packet bindings unavailable"
      :description="error"
      tone="error"
      aria-live="polite"
    >
      <template #action>
        <CButton id="retry-telemetry-decom" size="sm" @click="retryQuery"> Retry query </CButton>
      </template>
    </CStatePanel>

    <template v-else-if="presentation">
      <aside
        v-if="actionPending"
        id="telemetry-decom-action-loading"
        role="status"
        aria-live="polite"
      >
        Submitting the packet bindings action…
      </aside>
      <aside
        v-if="actionError"
        id="telemetry-decom-action-error"
        role="alert"
        aria-live="assertive"
      >
        {{ actionError }}
      </aside>
      <aside
        v-if="actionNotice"
        id="telemetry-decom-action-notice"
        role="status"
        aria-live="polite"
      >
        {{ actionNotice }}
      </aside>

      <ApplicationHost
        v-bind="presentation"
        @application_action="submitApplicationAction"
        @application_form_change="ignoreApplicationFormChange"
        @application_table_page="ignoreApplicationTablePage"
      />
    </template>
  </div>
</template>
