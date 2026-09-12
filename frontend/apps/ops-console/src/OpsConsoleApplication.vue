<script setup lang="ts">
import type { FullPageSurfaceProps, HostActionReceipt } from "@cadence/plugin-sdk";
import { computed, onBeforeUnmount, onMounted, provide, ref, shallowRef } from "vue";
import { FLEET_DIRECTORY_PORT } from "@cadence/planning-and-contacts/fleet-planning";
import { createFleetDirectoryPort } from "./fleet-directory-port";
import { FLEET_START_PORT } from "@cadence/planning-and-contacts/fleet-planning";
import { createFleetRunPort } from "./fleet-run-port";
import { FLEET_RUN_PORT } from "@cadence/planning-and-contacts/fleet-planning";
import { createFleetStartPort } from "./fleet-start-port";
import { PLAN_DETAIL_PORT } from "@cadence/planning-and-contacts/contact-plans";
import {
  CONTACT_SCHEDULE_PORT,
  CONTACT_RECORD_PORT,
} from "@cadence/planning-and-contacts/contact-scheduling";
import { createContactSchedulePort } from "./contact-schedule-port";
import { createContactRecordPort } from "./contact-record-port";
import { RESERVATION_PORT } from "@cadence/planning-and-contacts/contact-scheduling";
import { createReservationPort } from "./reservation-port";
import { createPlanDetailPort } from "./plan-detail-port";
import { OPS_COMPONENTS } from "./ops-components";
import { OPS_EVENT_BRIDGE, type OpsEventPayload } from "./ops-events";
import { unwrapOpsConsoleResponse, type OpsConsolePresentation } from "./ops-console";
import { reconcileOpsActionResult } from "./ops-action-results";
import { CHART_RUNTIME_PORT } from "@cadence/dashboards-and-exploration/workspace";

const props = defineProps<FullPageSurfaceProps>();
const presentation = shallowRef<OpsConsolePresentation>();
const loading = ref(true);
const error = ref<string>();
const actionPending = ref(false);
const actionNotice = ref<string>();
let loadGeneration = 0;
let actionGeneration = 0;
let planPortActive = true;
const capturedContext = props.context;
const capturedSurface = props.surface;
const planPort = createPlanDetailPort(
  props,
  () => planPortActive && props.context === capturedContext && props.surface === capturedSurface,
);
if (planPort) provide(PLAN_DETAIL_PORT, planPort);
const reservationPort = createReservationPort(
  props,
  () => planPortActive && props.context === capturedContext && props.surface === capturedSurface,
);
if (reservationPort) provide(RESERVATION_PORT, reservationPort);
const recordPort = createContactRecordPort(
  props,
  () => planPortActive && props.context === capturedContext && props.surface === capturedSurface,
);
if (recordPort) provide(CONTACT_RECORD_PORT, recordPort);
const schedulePort = createContactSchedulePort(
  props,
  () => planPortActive && props.context === capturedContext && props.surface === capturedSurface,
);
if (schedulePort) provide(CONTACT_SCHEDULE_PORT, schedulePort);

const fleetDirectoryPort = createFleetDirectoryPort(
  props,
  () => planPortActive && props.context === capturedContext && props.surface === capturedSurface,
);
if (fleetDirectoryPort) provide(FLEET_DIRECTORY_PORT, fleetDirectoryPort);

const fleetStartPort = createFleetStartPort(
  props,
  () => planPortActive && props.context === capturedContext && props.surface === capturedSurface,
);
if (fleetStartPort) provide(FLEET_START_PORT, fleetStartPort);
const fleetRunPort = createFleetRunPort(
  props,
  () => planPortActive && props.context === capturedContext && props.surface === capturedSurface,
);
if (fleetRunPort) provide(FLEET_RUN_PORT, fleetRunPort);

const draftPreservingActions = new Set([
  "validate",
  "validate-template",
  "validate-settings",
  "validate-request",
  "validate-fleet-run",
  "validate-policy",
  "validate-grant",
  "filter",
  "reset_filters",
  "filter_dashboards",
  "search",
  "apply_timeline_filters",
  "clear_timeline_selection",
]);

const actionListeners = computed(() =>
  Object.fromEntries(
    (planPort ||
    reservationPort ||
    recordPort ||
    schedulePort ||
    fleetDirectoryPort ||
    fleetStartPort ||
    fleetRunPort
      ? []
      : props.surface.actions
    ).map((actionId) => [actionId, (input: unknown) => void executeAction(actionId, input)]),
  ),
);

provide(OPS_EVENT_BRIDGE, props.bridge);
// Compatibility transport only. Module-owned charts never discover the Ops
// application's browser event bus or inherit its unrestricted action bridge.
provide(CHART_RUNTIME_PORT, {
  version: 1,
  execute(action, payload) {
    if (!props.surface.actions.includes(action)) return;
    return executeAction(action, payload);
  },
  subscribe(topic, listener) {
    const name = topic === "append" ? "tlm:append" : "tlm:select";
    const receive = (event: Event) => {
      if (event instanceof CustomEvent) listener(event.detail);
    };
    window.addEventListener(name, receive);
    return () => window.removeEventListener(name, receive);
  },
});

onMounted(() => {
  window.addEventListener("cadence:ops-event", onOpsEvent);
  void loadSurface();
});

onBeforeUnmount(() => {
  planPortActive = false;
  window.removeEventListener("cadence:ops-event", onOpsEvent);
  loadGeneration += 1;
  actionGeneration += 1;
});

async function loadSurface(): Promise<void> {
  const generation = ++loadGeneration;
  loading.value = true;
  error.value = undefined;
  presentation.value = undefined;

  try {
    const response = await props.bridge.query<unknown>({
      queryId: props.surface.dataContract.id,
      version: props.surface.dataContract.version,
      context: props.context,
    });
    if (generation !== loadGeneration) return;
    presentation.value = unwrapOpsConsoleResponse(response, OPS_COMPONENTS);
  } catch (reason) {
    if (generation !== loadGeneration) return;
    error.value = reason instanceof Error ? reason.message : "The Ops Console query failed.";
  } finally {
    if (generation === loadGeneration) loading.value = false;
  }
}

async function onOpsEvent(event: Event): Promise<void> {
  if (
    planPort ||
    reservationPort ||
    recordPort ||
    schedulePort ||
    fleetDirectoryPort ||
    fleetStartPort ||
    fleetRunPort ||
    !(event instanceof CustomEvent)
  )
    return;

  const detail = event.detail as { eventName?: string; payload?: OpsEventPayload };
  const actionId = detail.eventName;
  if (!actionId || actionPending.value) return;
  if (!props.surface.actions.includes(actionId)) {
    error.value = `Phoenix did not declare ${actionId} for ${props.surface.surfaceId}.`;
    return;
  }

  await executeAction(actionId, detail.payload);
}

async function executeAction(actionId: string, input: unknown): Promise<void> {
  if (actionPending.value) return;

  const generation = ++actionGeneration;
  actionPending.value = true;
  actionNotice.value = undefined;
  error.value = undefined;

  try {
    const receipt = await props.bridge.execute({
      applicationKey: props.application.applicationKey,
      applicationVersion: props.application.applicationVersion,
      surfaceId: props.surface.surfaceId,
      surfaceVersion: 1,
      actionId,
      input: actionInput(input),
      context: props.context,
    });
    if (generation !== actionGeneration) return;
    assertCompletedReceipt(receipt, actionId);

    if (draftPreservingActions.has(actionId)) {
      if (!presentation.value) throw new Error("The Ops Console presentation is unavailable.");
      presentation.value = reconcileOpsActionResult(
        presentation.value,
        props.surface.surfaceId,
        actionId,
        receipt.result,
      );
    }

    window.dispatchEvent(
      new CustomEvent("cadence:ops-action-result", {
        detail: { actionId, result: receipt.result },
      }),
    );

    const navigation = navigationHref(receipt.result);
    if (navigation) {
      (props.bridge.navigate ?? ((target) => window.location.assign(target)))(navigation);
      return;
    }

    actionNotice.value = `${actionId} completed.`;
    if (!draftPreservingActions.has(actionId)) await loadSurface();
  } catch (reason) {
    if (generation !== actionGeneration) return;
    error.value = reason instanceof Error ? reason.message : "The Ops Console action failed.";
  } finally {
    if (generation === actionGeneration) actionPending.value = false;
  }
}

function assertCompletedReceipt(
  receipt: HostActionReceipt<unknown>,
  actionId: string,
): asserts receipt is HostActionReceipt<unknown> {
  if (
    !isRecord(receipt) ||
    !nonEmptyString(receipt.receiptId) ||
    !nonEmptyString(receipt.completedAt) ||
    !("result" in receipt)
  ) {
    throw new Error("Phoenix did not return a completed action receipt.");
  }

  const result = receipt.result;
  if (!isRecord(result)) return;

  if (
    ("surfaceId" in result && result.surfaceId !== props.surface.surfaceId) ||
    ("actionId" in result && result.actionId !== actionId)
  ) {
    throw new Error("Phoenix returned an action receipt for a different Ops surface.");
  }
}

function navigationHref(result: unknown): string | undefined {
  if (!isRecord(result)) return undefined;

  const navigation = result.navigation ?? result.navigate;
  const candidate =
    typeof navigation === "string"
      ? navigation
      : isRecord(navigation)
        ? (navigation.href ?? navigation.path)
        : undefined;

  if (!nonEmptyString(candidate)) return undefined;

  try {
    const url = new URL(candidate, window.location.origin);
    if (
      url.origin !== window.location.origin ||
      url.username !== "" ||
      url.password !== "" ||
      !url.pathname.startsWith("/")
    ) {
      return undefined;
    }
    return url.href;
  } catch {
    return undefined;
  }
}

function nonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function actionInput(input: unknown): Record<string, unknown> {
  const next = isRecord(input) ? { ...input } : {};
  const page = isRecord(presentation.value?.props.page) ? presentation.value.props.page : undefined;
  const dashboardId = page && typeof page.dashboard_id === "string" ? page.dashboard_id : undefined;

  if (dashboardId && !next.dashboard_id) next.dashboard_id = dashboardId;
  return next;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
</script>

<template>
  <div
    id="ops-console-application"
    class="ops-console-application"
    :data-ops-console-surface="props.surface.surfaceId"
    data-ops-console-renderer="federated-surface"
  >
    <section
      v-if="loading"
      id="ops-console-loading"
      class="card min-h-80 border border-base-300 bg-base-200"
      aria-live="polite"
    >
      <div class="card-body flex items-center justify-center gap-5 p-8 text-base-content/70">
        <span class="loading loading-spinner loading-md" aria-label="Loading Ops Console"></span>
        <div>
          <strong class="mb-1 block text-lg font-medium tracking-tight text-base-content"
            >Loading Ops Console</strong
          >
          <p class="text-sm leading-6">
            Requesting the mission-scoped operations presentation from Phoenix.
          </p>
        </div>
      </div>
    </section>
    <section
      v-else-if="error"
      id="ops-console-error"
      class="card border border-error/40 bg-base-200"
      aria-live="polite"
    >
      <div class="card-body p-6">
        <div class="flex items-start gap-3">
          <span
            class="grid size-10 shrink-0 place-items-center border border-error font-mono text-error"
            aria-hidden="true"
            >!</span
          >
          <div>
            <strong class="block text-lg font-medium tracking-tight text-base-content"
              >Ops Console unavailable</strong
            >
            <p class="mt-1 text-sm leading-6 text-base-content/70">{{ error }}</p>
            <button
              id="retry-ops-console"
              type="button"
              class="btn btn-sm mt-5"
              @click="loadSurface"
            >
              Retry query
            </button>
          </div>
        </div>
      </div>
    </section>
    <template v-else-if="presentation">
      <aside
        v-if="actionPending"
        id="ops-console-action-loading"
        role="status"
        aria-live="polite"
        class="mb-4 border border-info/40 bg-info/10 px-4 py-3 text-sm text-base-content"
      >
        Sending the operation to Phoenix…
      </aside>
      <aside
        v-if="actionNotice"
        id="ops-console-action-notice"
        role="status"
        aria-live="polite"
        class="mb-4 border border-success/40 bg-success/10 px-4 py-3 text-sm text-base-content"
      >
        {{ actionNotice }}
      </aside>
      <component
        :is="OPS_COMPONENTS[presentation.component]"
        v-bind="
          ['OpsConsoleLanding', 'OpsDashboardNew', 'OpsDashboardDirectory'].includes(
            presentation.component,
          )
            ? {
                ...presentation.props,
                organizationId: context.organizationId,
                missionId: context.missionId,
              }
            : presentation.props
        "
        v-on="actionListeners"
      />
    </template>
  </div>
</template>
