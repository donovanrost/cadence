<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, shallowRef, watch } from "vue";
import type { RouteLocationNormalized } from "vue-router";
import { isNavigationFailure, NavigationFailureType } from "vue-router";
import type {
  OpsPageNavigationResult,
  OpsPageUpdateSubscription,
} from "@cadence/plugin-sdk/ops-pages";
import { readHostSnapshot, requireRecord, errorMessage, type HostSnapshot } from "./host-snapshot";
import { record } from "./snapshot-readers";
import { useLiveVue } from "live_vue";
import HostPage from "./HostPage.vue";
import { workspaceGroups } from "../ops-workspace/shared/destinations";
import { breadcrumbTrail } from "./breadcrumbs";
import { lazyHostPage } from "./lazy-host-page";
import ApplicationShell from "./ApplicationShell.vue";
import {
  createHostRouter,
  hostRoute,
  installHostNavigation,
  shellForRoute,
} from "./host-navigation";
import { hostBrowserHistory, ownBrowserHistory } from "./host-browser-history";
import {
  createConfigurationDrafts,
  createConfigurationPort,
  readConfiguration,
} from "../mission-and-spacecraft/configuration";
import type { SettingsContext, SettingsWriteResult } from "@cadence/plugin-sdk/settings";
import { createSettingsDrafts, type SettingsAction } from "../settings";
const SettingsPage = lazyHostPage("SettingsPage", () => import("../settings/SettingsPage.vue"));

const InstallationManagementPage = lazyHostPage(
  "InstallationManagementPage",
  () =>
    import("../capability-management/features/application-installations/InstallationManagementPage.vue"),
);
const AdministrationDiagnosticsPage = lazyHostPage(
  "AdministrationDiagnosticsPage",
  () => import("../administration/features/diagnostics/AdministrationDiagnosticsPage.vue"),
);
const CatalogPage = lazyHostPage("CatalogPage", () => import("../catalog/CatalogPage.vue"));
const AdministrationPage = lazyHostPage(
  "AdministrationPage",
  () => import("../administration/AdministrationPage.vue"),
);
const PlatformAdministrationPage = lazyHostPage(
  "PlatformAdministrationPage",
  () => import("../administration/PlatformAdministrationPage.vue"),
);
const NotificationsPage = lazyHostPage(
  "NotificationsPage",
  () => import("../auth-and-navigation/features/notifications/NotificationsPage.vue"),
);
const WorkspaceLanding = lazyHostPage(
  "WorkspaceLanding",
  () => import("../ops-workspace/features/landing/WorkspaceLanding.vue"),
);
const TimelinePage = lazyHostPage(
  "TimelinePage",
  () => import("../ops-workspace/features/timeline/TimelinePage.vue"),
);
const MissionPage = lazyHostPage(
  "MissionPage",
  () => import("../mission-and-spacecraft/MissionPage.vue"),
);
const SpacecraftPage = lazyHostPage(
  "SpacecraftPage",
  () => import("../mission-and-spacecraft/SpacecraftPage.vue"),
);
const SpacecraftModulePage = lazyHostPage(
  "SpacecraftModulePage",
  () => import("../mission-and-spacecraft/features/module-pages/SpacecraftModulePage.vue"),
);
const MissionModulePage = lazyHostPage(
  "MissionModulePage",
  () => import("../mission-and-spacecraft/features/module-pages/MissionModulePage.vue"),
);
const OpsModulePage = lazyHostPage(
  "OpsModulePage",
  () => import("../ops-workspace/features/module-pages/OpsModulePage.vue"),
);
const OrganizationModulePage = lazyHostPage(
  "OrganizationModulePage",
  () => import("../administration/features/module-pages/OrganizationModulePage.vue"),
);
const ActivationApprovalsPage = lazyHostPage(
  "ActivationApprovalsPage",
  () =>
    import("../capability-management/features/activation-approvals/ActivationApprovalsPage.vue"),
);

const props = defineProps<{ snapshot: unknown }>();
const initialSnapshot = readHostSnapshot(props.snapshot);
const live = useLiveVue();
const configurationDrafts = createConfigurationDrafts();
const settingsDrafts = createSettingsDrafts();
const configurationPort = createConfigurationPort(configurationRequest);
// A native Phoenix navigation can mount this host after the history module loaded.
hostBrowserHistory.replace(initialSnapshot.path + window.location.hash);
const router = createHostRouter(hostBrowserHistory);
type CommittedPage = {
  route: RouteLocationNormalized;
  snapshot: HostSnapshot;
  params: Record<string, string>;
};
const committed = shallowRef<CommittedPage | null>(null);
function currentPage(): CommittedPage {
  if (!committed.value) throw new Error("The host page is unavailable.");
  return committed.value;
}
function field(value: unknown, ...keys: string[]): unknown {
  for (const key of keys) {
    if (!record(value)) return undefined;
    value = value[key];
  }
  return value;
}
const failure = shallowRef<string | null>(null);
const pending = shallowRef(false);
const refreshingDiagnostics = shallowRef(false);
let generation = 0;
let stopped = false;
let removeLinks: (() => void) | undefined;
let bootstrap: HostSnapshot | null = initialSnapshot;
const opsUpdateListeners = new Set<(value: unknown) => void>();
let opsUpdatesRef: ReturnType<typeof live.handleEvent> | undefined;
const subscribeOpsUpdates: OpsPageUpdateSubscription = (request, listener) => {
  const path = currentPage().snapshot.path;
  const notify = (value: unknown) => {
    if (
      record(value) &&
      value.path === path &&
      value.id === request.id &&
      value.token === request.token &&
      committed.value?.snapshot.path === path &&
      !stopped
    )
      listener();
  };
  opsUpdateListeners.add(notify);
  return () => opsUpdateListeners.delete(notify);
};

const pendingRequests = new Set<() => void>();
function request(event: string, payload: Record<string, unknown>): Promise<unknown> {
  return new Promise((resolve, reject) => {
    let settled = false;
    const finish = (
      outcome: { status: "ok"; snapshot: unknown } | { status: "failed"; error: Error },
    ) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      pendingRequests.delete(cancel);
      if (outcome.status === "failed") reject(outcome.error);
      else resolve(outcome.snapshot);
    };
    const fail = (message: string) => finish({ status: "failed", error: new Error(message) });
    const cancel = () => fail("The host was closed.");
    const timeout = setTimeout(() => fail("The connection is unavailable. Try again."), 10000);
    pendingRequests.add(cancel);
    try {
      live.pushEvent(event, payload, (reply: unknown) => {
        if (stopped) return cancel();
        if (record(reply) && reply.ok === true) finish({ status: "ok", snapshot: reply.snapshot });
        else fail("This page is unavailable.");
      });
    } catch (error) {
      fail(errorMessage(error));
    }
  });
}

let leaveGuard: (() => boolean) | null = null;
function guardNavigation(guard: () => boolean) {
  leaveGuard = guard;
  return () => {
    if (leaveGuard === guard) leaveGuard = null;
  };
}
function beforeUnload(event: BeforeUnloadEvent) {
  if (
    settingsDrafts.hasUnsaved() ||
    configurationDrafts.hasUnsaved() ||
    (leaveGuard && !leaveGuard())
  )
    event.preventDefault();
}
router.beforeEach(async (to, from) => {
  if (stopped) return false;
  if (to.fullPath !== from.fullPath && leaveGuard && !leaveGuard()) return false;
  if (!to.meta.host) {
    window.location.assign(to.fullPath);
    return false;
  }
  const currentGeneration = ++generation;
  pending.value = true;
  failure.value = null;
  try {
    const path = to.fullPath.replace(/#.*$/, "");
    const snapshot =
      bootstrap?.path === path
        ? bootstrap
        : readHostSnapshot(await request("host:context", { path }));
    bootstrap = null;
    if (stopped || currentGeneration !== generation) return false;
    to.meta.snapshot = snapshot;
    return true;
  } catch (error) {
    if (currentGeneration === generation) failure.value = errorMessage(error);
    return false;
  } finally {
    if (currentGeneration === generation) pending.value = false;
  }
});
router.afterEach((to, _from, navigationFailure) => {
  if (stopped || navigationFailure) return;
  if (!to.meta.host || !to.meta.snapshot) return;
  const params: Record<string, string> = {};
  for (const [key, value] of Object.entries(to.params))
    if (typeof value === "string") params[key] = value;
  committed.value = { route: to, snapshot: to.meta.snapshot, params };
  const title = to.meta.host.metadata.page_title;
  document.title = title ? `${title} · Cadence` : "Cadence";
});

// Live updates only affect the resource actually displayed. Guard responses are
// committed with their route, so rapid navigation cannot mix two mission contexts.
watch(
  () => props.snapshot,
  (value) => {
    try {
      const snapshot = readHostSnapshot(value);
      if (committed.value?.snapshot.path === snapshot.path && !pending.value)
        committed.value = { ...currentPage(), snapshot };
    } catch (error) {
      failure.value = errorMessage(error);
    }
  },
  { deep: true },
);
const route = computed(() => committed.value?.route.meta.host);
const context = computed(() => {
  const page = committed.value,
    selected = page?.route.meta.host;
  if (!page || !selected) return null;
  return {
    ...page.snapshot.context,
    nav_context: selected.scope,
    nav_item: null,
    ops_nav_item: "dashboards",
    active_dashboard_id: page.params.dashboard_id,
    ...selected.metadata,
  };
});
const organizationContext = computed(() => {
  const organizationId = context.value?.organization?.organization_id;
  const resourceId = committed.value?.params.provider_account_id;
  return organizationId ? { organizationId, ...(resourceId ? { resourceId } : {}) } : null;
});
const missionContext = computed(() => {
  const organizationId = context.value?.organization?.organization_id;
  const missionId = committed.value?.params.mission_id;
  const resourceId = route.value?.resourceParam
    ? committed.value?.params[route.value.resourceParam]
    : undefined;
  return organizationId && missionId
    ? { organizationId, missionId, ...(resourceId ? { resourceId } : {}) }
    : null;
});
const settingsContext = computed<SettingsContext | null>(() => {
  const current = context.value;
  if (!current?.user || !current.organization) return null;
  const identity = {
    actorId: current.user.user_id,
    organizationId: current.organization.organization_id,
    organizationName: current.organization.display_name,
  };
  return current.mission
    ? {
        ...identity,
        scope: "mission",
        missionId: current.mission.mission_id,
        missionName: current.mission.display_name,
      }
    : { ...identity, scope: "organization", missionId: null, missionName: null };
});
watch(
  () => context.value?.user?.user_id,
  (actor, previous) => {
    if (previous && actor !== previous) settingsDrafts.clear();
  },
);
const spacecraftContext = computed(() => {
  const mission = missionContext.value,
    spacecraftId = committed.value?.params.spacecraft_id;
  return mission && spacecraftId
    ? { organizationId: mission.organizationId, missionId: mission.missionId, spacecraftId }
    : null;
});
// A route may opt out of the host heading when its page renders its own identity bar.
const pageHeading = computed(
  () => !(route.value && "pageChrome" in route.value && route.value.pageChrome === "none"),
);
// The sidebar section names a page's place for its eyebrow (e.g. "Plan").
const pageSection = computed(() => {
  const item =
    route.value?.metadata && "ops_nav_item" in route.value.metadata
      ? route.value.metadata.ops_nav_item
      : undefined;
  if (!item) return null;
  return (
    workspaceGroups((path) => path, item).find((group) => group.items.some((i) => i.key === item))
      ?.label ?? null
  );
});
const pageTitle = computed(
  () => route.value?.metadata.page_title || context.value?.mission?.display_name || "Overview",
);
const pageBreadcrumbs = computed(() =>
  route.value && committed.value && context.value
    ? breadcrumbTrail(route.value, committed.value.route.path, context.value, pageTitle.value)
    : [],
);
const variant = computed(() => route.value && shellForRoute(route.value));
function navigate(href: string, replace = false) {
  const target = new URL(href, window.location.href);
  if (target.origin !== window.location.origin || !hostRoute(target)) {
    if (leaveGuard && !leaveGuard()) return;
    window.location.assign(target.href);
    return;
  }
  void navigateSettled(target.href, replace);
}
async function navigateSettled(href: string, replace = false): Promise<OpsPageNavigationResult> {
  try {
    const target = new URL(href, window.location.href);
    if (stopped || target.origin !== window.location.origin || !hostRoute(target)) return "failed";
    const path = target.pathname + target.search + target.hash;
    const result = await (replace ? router.replace(path) : router.push(path));
    if (isNavigationFailure(result, NavigationFailureType.duplicated)) return "unchanged";
    return result ? "cancelled" : "completed";
  } catch (error) {
    if (!stopped) failure.value = errorMessage(error);
    return "failed";
  }
}
async function manage(event: string, payload: Record<string, unknown>) {
  const path = currentPage().snapshot.path;
  const requestGeneration = generation;
  const snapshot = readHostSnapshot(await request("host:manage", { ...payload, event, path }));
  if (!stopped && generation === requestGeneration && currentPage().snapshot.path === path)
    committed.value = { ...currentPage(), snapshot };
}
async function reconnect() {
  if (!committed.value) return;
  const requestGeneration = generation;
  const path = currentPage().snapshot.path;
  try {
    const snapshot = readHostSnapshot(await request("host:context", { path }));
    if (!stopped && generation === requestGeneration && currentPage().snapshot.path === path) {
      failure.value = null;
      committed.value = { ...currentPage(), snapshot };
    }
  } catch (error) {
    if (!stopped && generation === requestGeneration && currentPage().snapshot.path === path)
      failure.value = errorMessage(error);
  }
}
async function catalogAction(event: "reimport") {
  const path = currentPage().snapshot.path;
  const requestGeneration = generation;
  const result = requireRecord(await request("host:catalog", { event, path }));
  if (!stopped && generation === requestGeneration && currentPage().snapshot.path === path) {
    if (typeof result.href !== "string") throw new Error("Invalid catalog destination.");
    navigate(result.href);
  }
}
function cancelCatalogUpload(params: Record<string, unknown>) {
  live.pushEvent("catalog:upload:cancel", params);
}
async function platformAdministrationAction(event: string, input: Record<string, unknown>) {
  const path = currentPage().snapshot.path;
  const requestGeneration = generation;
  const userId = context.value?.user?.user_id;
  const token = currentPage().snapshot.platform_administration_page?.action_token;
  const result = requireRecord(
    await request("host:platform-administration", { event, input, path, token }),
  );
  if (
    stopped ||
    generation !== requestGeneration ||
    currentPage().snapshot.path !== path ||
    context.value?.user?.user_id !== userId ||
    currentPage().snapshot.platform_administration_page?.action_token !== token
  )
    throw new Error("The administration context changed.");
  const host = readHostSnapshot(result.host);
  if (host.path !== path || host.context.user?.user_id !== userId)
    throw new Error("Invalid administration context.");
  committed.value = { ...currentPage(), snapshot: host };
  return result;
}
async function notificationAction(event: string, input: Record<string, unknown>) {
  const path = currentPage().snapshot.path;
  const requestGeneration = generation;
  const token = currentPage().snapshot.notifications_page?.action_token;
  const result = requireRecord(await request("host:notifications", { event, input, path, token }));
  if (stopped || generation !== requestGeneration || currentPage().snapshot.path !== path)
    throw new Error("The notification context changed.");
  const host = readHostSnapshot(result.host);
  if (host.path !== path || host.context.user?.user_id !== context.value?.user?.user_id)
    throw new Error("Invalid notification context.");
  committed.value = { ...currentPage(), snapshot: host };
  if (result.status === "ok" && field(result, "data", "status") === "accepted") {
    if (field(result, "data", "navigate") !== "/")
      throw new Error("Invalid invitation destination.");
    navigate("/");
  }
  return result;
}
async function missionAction(event: string, input: Record<string, unknown>) {
  const path = currentPage().snapshot.path;
  const requestGeneration = generation;
  const token = currentPage().snapshot.mission_page?.creation_token;
  const result = requireRecord(await request("host:mission", { event, input, path, token }));
  if (
    !stopped &&
    generation === requestGeneration &&
    currentPage().snapshot.path === path &&
    event === "save" &&
    result?.status === "ok"
  ) {
    const href = field(result, "data", "mission", "href");
    if (typeof href !== "string" || !/^\/missions\/[^/\\\s?#]+$/.test(href))
      throw new Error("Invalid mission destination.");
    navigate(href);
  }
  return result;
}
async function spacecraftAction(event: string, input: Record<string, unknown>) {
  const path = currentPage().snapshot.path;
  const requestGeneration = generation;
  const token = currentPage().snapshot.spacecraft_page?.form_token;
  const result = requireRecord(await request("host:spacecraft", { event, input, path, token }));
  if (
    !stopped &&
    generation === requestGeneration &&
    currentPage().snapshot.path === path &&
    event === "save" &&
    result?.status === "ok"
  ) {
    const href = field(result, "data", "href");
    const destination =
      `/missions/${currentPage().route.params.mission_id}/spacecraft` +
      (currentPage().snapshot.spacecraft_page?.page === "profile_new" ? "/profiles" : "");
    if (typeof href !== "string" || href !== destination)
      throw new Error("Invalid spacecraft destination.");
    navigate(href);
  }
  return result;
}
async function configurationRequest(event: string, input: Record<string, unknown>) {
  const path = currentPage().snapshot.path;
  const requestGeneration = generation;
  const userId = context.value?.user?.user_id;
  const result = requireRecord(
    await request("host:spacecraft-configuration", { event, input, path }),
  );
  if (
    stopped ||
    generation !== requestGeneration ||
    currentPage().snapshot.path !== path ||
    context.value?.user?.user_id !== userId
  )
    throw new Error("The spacecraft context changed.");
  const host = readHostSnapshot(result.host);
  if (host.path !== path || host.context.user?.user_id !== userId)
    throw new Error("Invalid spacecraft context.");
  if (event === "save" && result.status === "ok")
    configurationDrafts.acceptSaved(readConfiguration(host.spacecraft_page?.data));
  committed.value = { ...currentPage(), snapshot: host };
  return result;
}
async function refreshSettings() {
  const captured = currentPage();
  const requestGeneration = generation;
  const snapshot = readHostSnapshot(
    await request("host:context", { path: captured.snapshot.path }),
  );
  if (
    stopped ||
    pending.value ||
    requestGeneration !== generation ||
    currentPage().snapshot.path !== captured.snapshot.path ||
    snapshot.path !== captured.snapshot.path ||
    snapshot.context.user?.user_id !== captured.snapshot.context.user?.user_id
  )
    throw Error("The settings context changed.");
  committed.value = { ...currentPage(), snapshot };
}
async function settingsAction(action: SettingsAction): Promise<SettingsWriteResult> {
  const captured = currentPage();
  const requestGeneration = generation;
  const actorId = captured.snapshot.context.user?.user_id;
  const current = () =>
    !stopped &&
    !pending.value &&
    generation === requestGeneration &&
    currentPage().snapshot.path === captured.snapshot.path &&
    currentPage().snapshot.settings_page?.token === action.token &&
    context.value?.user?.user_id === actorId;
  if (!current()) return { status: "rejected", message: "This settings page is no longer active." };
  try {
    const response = requireRecord(
      await request("host:settings", {
        path: captured.snapshot.path,
        token: action.token,
        input: { revision_token: action.revisionToken, document: action.document },
      }),
    );
    if (!current()) return { status: "unconfirmed" };
    const host = readHostSnapshot(response.page);
    if (
      host.path !== captured.snapshot.path ||
      host.context.user?.user_id !== actorId ||
      host.context.organization?.organization_id !==
        captured.snapshot.context.organization?.organization_id ||
      host.settings_page?.token !== action.token
    )
      return { status: "unconfirmed" };
    const result = requireRecord(response.result);
    committed.value = { ...currentPage(), snapshot: host };
    if (result.status === "ok" && typeof result.revision_id === "string")
      return {
        status: "saved",
        revisionId: result.revision_id,
        snapshot: field(host.settings_page, "data", "settings"),
      };
    if (result.status === "rejected" && typeof result.message === "string")
      return { status: "rejected", message: result.message };
    return { status: "unconfirmed" };
  } catch {
    return { status: "unconfirmed" };
  }
}
async function activationDecision(input: unknown) {
  const path = currentPage().snapshot.path;
  const requestGeneration = generation;
  const token = currentPage().snapshot.activation_approvals?.token;
  const result = requireRecord(await request("host:activation", { path, token, input }));
  if (!stopped && generation === requestGeneration && currentPage().snapshot.path === path) {
    const page = readHostSnapshot(result.page);
    if (page.path !== path) throw new Error("Invalid activation response path.");
    committed.value = { ...currentPage(), snapshot: page };
  }
  return result.result;
}
async function organizationPageAction(payload: Record<string, unknown>) {
  const path = currentPage().snapshot.path,
    requestGeneration = generation;
  const page = currentPage().snapshot.organization_module_page;
  if (pending.value || payload.id !== page?.id || payload.token !== page?.token)
    throw new Error("Inactive organization page.");
  const result = await request("host:organization-page", { ...payload, path });
  if (stopped || generation !== requestGeneration || currentPage().snapshot.path !== path)
    throw new Error("Inactive organization page response.");
  return result;
}
async function opsPageAction(payload: Record<string, unknown>) {
  const path = currentPage().snapshot.path,
    requestGeneration = generation;
  const page = currentPage().snapshot.ops_page;
  if (pending.value || payload.id !== page?.id || payload.token !== page?.token)
    throw new Error("Inactive Ops page.");
  const result = await request("host:ops-page", { ...payload, path });
  if (stopped || generation !== requestGeneration || currentPage().snapshot.path !== path)
    throw new Error("Inactive Ops page response.");
  return result;
}
async function opsPageRead(payload: Record<string, unknown>) {
  const path = currentPage().snapshot.path,
    requestGeneration = generation,
    page = currentPage().snapshot.ops_page;
  if (
    pending.value ||
    route.value?.kind !== "ops_module" ||
    payload.id !== page?.id ||
    payload.token !== page?.token
  )
    throw new Error("Inactive Ops page read.");
  const result = await request("host:ops-page:read", { ...payload, path });
  if (
    stopped ||
    generation !== requestGeneration ||
    currentPage().snapshot.path !== path ||
    currentPage().snapshot.ops_page?.token !== payload.token
  )
    throw new Error("Inactive Ops page read response.");
  return result;
}
async function missionPageAction(payload: Record<string, unknown>) {
  const path = currentPage().snapshot.path,
    requestGeneration = generation;
  const page = currentPage().snapshot.mission_module_page;
  if (pending.value || payload.id !== page?.id || payload.token !== page?.token)
    throw new Error("Inactive mission page.");
  const result = await request("host:mission-page", { ...payload, path });
  if (stopped || generation !== requestGeneration || currentPage().snapshot.path !== path)
    throw new Error("Inactive mission page response.");
  return result;
}
async function refreshDiagnostics() {
  if (refreshingDiagnostics.value) return;
  refreshingDiagnostics.value = true;
  try {
    await reconnect();
  } finally {
    refreshingDiagnostics.value = false;
  }
}
function updateDiagnosticsQuery(query: Record<string, string>) {
  const search = new URLSearchParams(query).toString();
  navigate(`/admin/runtime${search ? `?${search}` : ""}`);
}
// Routing is private to this host; descendants navigate through the host bridge.
// Installing a plugin here would redefine app-wide $route when this component remounts.
void router.replace(hostBrowserHistory.location).catch((error) => {
  if (!stopped) failure.value = errorMessage(error);
});
onMounted(() => {
  window.addEventListener("beforeunload", beforeUnload);
  ownBrowserHistory(true);
  removeLinks = installHostNavigation(document, window.location, navigate);
  window.addEventListener("cadence:transport-reconnected", reconnect);
  opsUpdatesRef = live.handleEvent("cadence:ops-page-changed", (value: unknown) => {
    for (const listener of opsUpdateListeners) listener(value);
  });
});
onBeforeUnmount(() => {
  configurationDrafts.clear();
  settingsDrafts.clear();
  window.removeEventListener("beforeunload", beforeUnload);
  stopped = true;
  generation++;
  for (const cancel of pendingRequests) cancel();
  opsUpdateListeners.clear();
  if (opsUpdatesRef !== undefined) live.removeHandleEvent(opsUpdatesRef);
  removeLinks?.();
  ownBrowserHistory(false);
  window.removeEventListener("cadence:transport-reconnected", reconnect);
  router.listening = false;
  router.options.history.destroy();
});
</script>
<template>
  <ApplicationShell
    v-if="committed && route && variant && context"
    :variant="variant"
    :context="context"
    managed-page
  >
    <HostPage
      :key="
        route.kind === 'administration_diagnostics' || route.kind === 'spacecraft'
          ? committed.route.path
          : committed.route.fullPath
      "
      :title="pageTitle"
      :breadcrumbs="pageBreadcrumbs"
      :workspace="variant === 'ops'"
      :heading="pageHeading"
      :route="route.path"
      :section="pageSection"
    >
      <p v-if="failure" id="host-navigation-error" role="alert">{{ failure }}</p>
      <div :aria-busy="pending" :data-host-path="committed.snapshot.path">
        <div v-if="route.kind === 'application_management'" :id="route.mountId" class="contents">
          <InstallationManagementPage
            :scope="route.scope"
            :snapshot="committed.snapshot.application_management"
            :execute="manage"
            :refresh="reconnect"
          />
          <p v-if="committed.snapshot.error" id="application-management-error" role="alert">
            {{ committed.snapshot.error }}
          </p>
        </div>
        <SettingsPage
          v-else-if="route.kind === 'settings' && settingsContext"
          :id="route.mountId"
          :snapshot="committed.snapshot.settings_page"
          :context="settingsContext"
          :section-id="committed.params.section_id ?? 'cadence.governance'"
          :drafts="settingsDrafts"
          :execute="settingsAction"
          :refresh="refreshSettings"
          :navigating="pending"
        />
        <AdministrationDiagnosticsPage
          v-else-if="route.kind === 'administration_diagnostics'"
          :snapshots="committed.snapshot.diagnostics ?? []"
          :interactions="{ updateQuery: updateDiagnosticsQuery }"
          :refreshing="refreshingDiagnostics"
          @refresh="refreshDiagnostics"
        />
        <ActivationApprovalsPage
          v-else-if="route.kind === 'activation_approvals' && missionContext"
          :id="route.mountId"
          :snapshot="committed.snapshot.activation_approvals"
          :context="{
            organization_id: missionContext.organizationId,
            mission_id: missionContext.missionId,
          }"
          :execute="activationDecision"
          :refresh="reconnect"
          :navigating="pending"
        />
        <OrganizationModulePage
          v-else-if="route.kind === 'organization_module' && organizationContext"
          :id="route.mountId"
          :contribution-id="route.contribution"
          :snapshot="committed.snapshot.organization_module_page"
          :context="organizationContext"
          :execute="organizationPageAction"
          :navigate="navigate"
          :refresh="reconnect"
          :refreshing="pending"
        />
        <OpsModulePage
          v-else-if="route.kind === 'ops_module' && missionContext"
          :id="route.mountId"
          :contribution-id="route.contribution"
          :snapshot="committed.snapshot.ops_page"
          :context="missionContext"
          :execute="opsPageAction"
          :query="opsPageRead"
          :subscribe="subscribeOpsUpdates"
          :navigate="navigate"
          :navigate-settled="navigateSettled"
          :guard-navigation="guardNavigation"
          :refresh="reconnect"
          :refreshing="pending"
        />
        <MissionModulePage
          v-else-if="route.kind === 'mission_module' && missionContext"
          :id="route.mountId"
          :contribution-id="route.contribution"
          :snapshot="committed.snapshot.mission_module_page"
          :execute="missionPageAction"
          :navigate="navigate"
          :context="missionContext"
          :refresh="reconnect"
          :refreshing="pending"
        />
        <SpacecraftModulePage
          v-else-if="route.kind === 'spacecraft_module' && spacecraftContext"
          :id="route.mountId"
          :contribution-id="route.contribution"
          :snapshot="committed.snapshot.spacecraft_module_page"
          :context="spacecraftContext"
          :refresh="reconnect"
          :refreshing="pending"
        />
        <SpacecraftPage
          v-else-if="route.kind === 'spacecraft'"
          :id="route.mountId"
          :page="route.spacecraftPage"
          :class="route.viewClass"
          :snapshot="committed.snapshot.spacecraft_page"
          v-bind="
            spacecraftContext
              ? { configurationIdentity: spacecraftContext, configurationPort, configurationDrafts }
              : {}
          "
          :execute="spacecraftAction"
          :navigating="pending"
          :navigate="navigate"
          :refresh="reconnect"
        />
        <NotificationsPage
          v-else-if="route.kind === 'notifications'"
          :key="context.user?.user_id ?? 'anonymous'"
          :snapshot="committed.snapshot.notifications_page"
          :user-id="context.user?.user_id"
          :act="notificationAction"
          :refresh="reconnect"
        />
        <WorkspaceLanding
          v-else-if="
            route.kind === 'ops_workspace' && route.workspacePage === 'landing' && missionContext
          "
          :id="route.mountId"
          :model="committed.snapshot.ops_landing_page"
          :organization-id="missionContext.organizationId"
          :mission-id="missionContext.missionId"
        />
        <TimelinePage
          v-else-if="
            route.kind === 'ops_workspace' && route.workspacePage === 'timeline' && missionContext
          "
          :id="route.mountId"
          :snapshot="committed.snapshot.timeline_page"
          :organization-id="missionContext.organizationId"
          :mission-id="missionContext.missionId"
          :navigate="navigate"
          :refresh="reconnect"
        />
        <PlatformAdministrationPage
          v-else-if="route.kind === 'platform_administration'"
          :key="`${context.user?.user_id}:${committed.snapshot.path}`"
          :id="route.mountId"
          :page="route.administrationPage"
          :snapshot="committed.snapshot.platform_administration_page"
          :user-id="context.user?.user_id"
          :organization-id="committed.params.org_id"
          :csrf-token="context.csrf_token"
          :act="platformAdministrationAction"
          :refresh="reconnect"
        />
        <AdministrationPage
          v-else-if="route.kind === 'administration'"
          :id="route.mountId"
          :page="route.administrationPage"
          :snapshot="committed.snapshot.administration_page"
          :organization-id="context.organization?.organization_id"
          :refresh="reconnect"
        />
        <MissionPage
          v-else-if="route.kind === 'mission'"
          :id="route.mountId"
          :page="route.missionPage"
          :class="route.viewClass"
          :snapshot="committed.snapshot.mission_page"
          :execute="missionAction"
          :refresh="reconnect"
        />
        <CatalogPage
          v-else-if="route.kind === 'catalog'"
          :id="route.mountId"
          :page="route.catalogPage"
          :snapshot="committed.snapshot.catalog"
          :execute="catalogAction"
          :refresh="reconnect"
          :cancel-upload="cancelCatalogUpload"
          :navigate="navigate"
        />
        <p v-else id="host-route-unavailable" role="alert">This page is unavailable.</p>
      </div>
    </HostPage>
  </ApplicationShell>
  <p v-else-if="failure" id="host-navigation-error" role="alert">{{ failure }}</p>
  <p v-else role="status">Loading…</p>
</template>
