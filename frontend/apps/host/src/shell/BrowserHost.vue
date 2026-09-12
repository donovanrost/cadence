<script setup>
import { computed, onBeforeUnmount, onMounted, shallowRef, watch } from "vue";
import { useLiveVue } from "live_vue";
import HostPage from "./HostPage.vue";
import ApplicationShell from "./ApplicationShell.vue";
import InstallationManagementPage from "../capability-management/features/application-installations/InstallationManagementPage.vue";
import RoutedFederationSurface from "./RoutedFederationSurface.vue";
import AdministrationDiagnosticsPage from "../administration/features/diagnostics/AdministrationDiagnosticsPage.vue";
import CatalogPage from "../catalog/CatalogPage.vue";
import AdministrationPage from "../administration/AdministrationPage.vue";
import PlatformAdministrationPage from "../administration/PlatformAdministrationPage.vue";
import NotificationsPage from "../auth-and-navigation/features/notifications/NotificationsPage.vue";
import WorkspaceLanding from "../ops-workspace/features/landing/WorkspaceLanding.vue";
import TimelinePage from "../ops-workspace/features/timeline/TimelinePage.vue";
import MissionPage from "../mission-and-spacecraft/MissionPage.vue";
import SpacecraftPage from "../mission-and-spacecraft/SpacecraftPage.vue";
import SpacecraftModulePage from "../mission-and-spacecraft/features/module-pages/SpacecraftModulePage.vue";
import MissionModulePage from "../mission-and-spacecraft/features/module-pages/MissionModulePage.vue";
import OpsModulePage from "../ops-workspace/features/module-pages/OpsModulePage.vue";
import OrganizationModulePage from "../administration/features/module-pages/OrganizationModulePage.vue";
import ActivationApprovalsPage from "../capability-management/features/activation-approvals/ActivationApprovalsPage.vue";
import {
  createHostRouter,
  hostRoute,
  installHostNavigation,
  shellForRoute,
} from "./host-navigation";
import { hostBrowserHistory, ownBrowserHistory } from "./host-browser-history";

const props = defineProps({ snapshot: { type: Object, required: true } });
const live = useLiveVue();
// A native Phoenix navigation can mount this host after the history module loaded.
hostBrowserHistory.replace(props.snapshot.path + window.location.hash);
const router = createHostRouter(hostBrowserHistory);
const committed = shallowRef(null);
const failure = shallowRef(null);
const pending = shallowRef(false);
const refreshingDiagnostics = shallowRef(false);
let generation = 0;
let stopped = false;
let removeLinks;
let bootstrap = props.snapshot;

const pendingRequests = new Set();
function request(event, payload) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const finish = (error, snapshot) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      pendingRequests.delete(cancel);
      error ? reject(error) : resolve(snapshot);
    };
    const cancel = () => finish(new Error("The host was closed."));
    const timeout = setTimeout(
      () => finish(new Error("The connection is unavailable. Try again.")),
      10000,
    );
    pendingRequests.add(cancel);
    try {
      live.pushEvent(event, payload, (reply) => {
        if (stopped) return cancel();
        reply?.ok ? finish(null, reply.snapshot) : finish(new Error("This page is unavailable."));
      });
    } catch (error) {
      finish(error);
    }
  });
}

let leaveGuard = null;
function guardNavigation(guard) {
  leaveGuard = guard;
  return () => {
    if (leaveGuard === guard) leaveGuard = null;
  };
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
    const path = to.fullPath.split("#")[0];
    const snapshot = bootstrap?.path === path ? bootstrap : await request("host:context", { path });
    bootstrap = null;
    if (stopped || currentGeneration !== generation) return false;
    to.meta.snapshot = snapshot;
    return true;
  } catch (error) {
    if (currentGeneration === generation) failure.value = error.message;
    return false;
  } finally {
    if (currentGeneration === generation) pending.value = false;
  }
});
router.afterEach((to, _from, navigationFailure) => {
  if (stopped || navigationFailure) return;
  committed.value = { route: to, snapshot: to.meta.snapshot };
  const title = to.meta.host.metadata.page_title;
  document.title = title ? `${title} · Cadence` : "Cadence";
});

// Live updates only affect the resource actually displayed. Guard responses are
// committed with their route, so rapid navigation cannot mix two mission contexts.
watch(
  () => props.snapshot,
  (snapshot) => {
    if (committed.value?.snapshot.path === snapshot.path && !pending.value)
      committed.value = { ...committed.value, snapshot };
  },
);
const route = computed(() => committed.value?.route.meta.host);
const context = computed(() => ({
  ...committed.value?.snapshot.context,
  nav_context: route.value?.scope,
  nav_item: null,
  ops_nav_item: "dashboards",
  active_dashboard_id: committed.value?.route.params.dashboard_id,
  ...route.value?.metadata,
}));
const pageTitle = computed(
  () => route.value?.metadata.page_title || context.value.mission?.display_name || "Overview",
);
const pageBreadcrumbs = computed(() => {
  const items = [];
  const current = context.value;
  if (route.value?.scope === "admin") items.push({ label: "Platform", href: "/admin" });
  else if (route.value?.scope === "user") items.push({ label: "Account" });
  else {
    items.push({ label: current.organization?.display_name || "Organization", href: "/" });
    if (current.mission)
      items.push({
        label: current.mission.display_name,
        href: `/missions/${encodeURIComponent(current.mission.mission_id)}`,
      });
    if (current.spacecraft)
      items.push({
        label: current.spacecraft.display_name,
        href: `/missions/${encodeURIComponent(current.mission.mission_id)}/spacecraft/${encodeURIComponent(current.spacecraft.spacecraft_id)}`,
      });
  }
  const path = committed.value?.route.path;
  if (items.at(-1)?.href === path) items[items.length - 1] = { label: items.at(-1).label };
  else items.push({ label: pageTitle.value });
  return items;
});
const variant = computed(() => route.value && shellForRoute(route.value));
const surfaceProps = computed(() => {
  if (!route.value) return {};
  const { params, query } = committed.value.route;
  const selected = route.value;
  const values = { ...query, ...params };
  const queryParams = Object.fromEntries(
    selected.queryKeys.flatMap((key) => {
      const value = values[selected.queryAliases[key] || key];
      return value === undefined ? [] : [[key, value]];
    }),
  );
  return {
    applicationKey: selected.application,
    surfaceId: selected.surface,
    hostScope: selected.scope,
    organizationId:
      selected.scope === "organization" ? context.value.organization?.organization_id : undefined,
    userId: selected.scope === "user" ? context.value.user?.user_id : undefined,
    missionId: params.mission_id,
    spacecraftId: params.spacecraft_id,
    queryParams,
  };
});
function navigate(href, replace = false) {
  const target = new URL(href, window.location.href);
  if (target.origin !== window.location.origin || !hostRoute(target)) {
    window.location.assign(target.href);
    return;
  }
  const path = target.pathname + target.search + target.hash;
  void (replace ? router.replace(path) : router.push(path));
}
async function manage(event, payload) {
  const path = committed.value.snapshot.path;
  const requestGeneration = generation;
  const snapshot = await request("host:manage", { ...payload, event, path });
  if (!stopped && generation === requestGeneration && committed.value.snapshot.path === path)
    committed.value = { ...committed.value, snapshot };
}
async function reconnect() {
  if (!committed.value) return;
  const requestGeneration = generation;
  const path = committed.value.snapshot.path;
  try {
    const snapshot = await request("host:context", { path });
    if (!stopped && generation === requestGeneration && committed.value.snapshot.path === path) {
      failure.value = null;
      committed.value = { ...committed.value, snapshot };
    }
  } catch (error) {
    if (!stopped && generation === requestGeneration && committed.value.snapshot.path === path)
      failure.value = error.message;
  }
}
async function catalogAction(event) {
  const path = committed.value.snapshot.path;
  const requestGeneration = generation;
  const result = await request("host:catalog", { event, path });
  if (!stopped && generation === requestGeneration && committed.value.snapshot.path === path)
    navigate(result.href);
}
function cancelCatalogUpload(params) {
  live.pushEvent("catalog:upload:cancel", params);
}
async function platformAdministrationAction(event, input) {
  const path = committed.value.snapshot.path;
  const requestGeneration = generation;
  const userId = context.value.user?.user_id;
  const token = committed.value.snapshot.platform_administration_page?.action_token;
  const result = await request("host:platform-administration", { event, input, path, token });
  if (
    stopped ||
    generation !== requestGeneration ||
    committed.value.snapshot.path !== path ||
    context.value.user?.user_id !== userId ||
    committed.value.snapshot.platform_administration_page?.action_token !== token
  )
    throw new Error("The administration context changed.");
  if (!result?.host || result.host.path !== path || result.host.context?.user?.user_id !== userId)
    throw new Error("Invalid administration context.");
  committed.value = { ...committed.value, snapshot: result.host };
  return result;
}
async function notificationAction(event, input) {
  const path = committed.value.snapshot.path;
  const requestGeneration = generation;
  const token = committed.value.snapshot.notifications_page?.action_token;
  const result = await request("host:notifications", { event, input, path, token });
  if (stopped || generation !== requestGeneration || committed.value.snapshot.path !== path)
    throw new Error("The notification context changed.");
  if (
    !result?.host ||
    result.host.path !== path ||
    result.host.context?.user?.user_id !== context.value.user?.user_id
  )
    throw new Error("Invalid notification context.");
  committed.value = { ...committed.value, snapshot: result.host };
  if (result.status === "ok" && result.data?.status === "accepted") {
    if (result.data.navigate !== "/") throw new Error("Invalid invitation destination.");
    navigate("/");
  }
  return result;
}
async function missionAction(event, input) {
  const path = committed.value.snapshot.path;
  const requestGeneration = generation;
  const token = committed.value.snapshot.mission_page?.creation_token;
  const result = await request("host:mission", { event, input, path, token });
  if (
    !stopped &&
    generation === requestGeneration &&
    committed.value.snapshot.path === path &&
    event === "save" &&
    result?.status === "ok"
  ) {
    const href = result.data?.mission?.href;
    if (typeof href !== "string" || !/^\/missions\/[^/\\\s?#]+$/.test(href))
      throw new Error("Invalid mission destination.");
    navigate(href);
  }
  return result;
}
async function spacecraftAction(event, input) {
  const path = committed.value.snapshot.path;
  const requestGeneration = generation;
  const token = committed.value.snapshot.spacecraft_page?.form_token;
  const result = await request("host:spacecraft", { event, input, path, token });
  if (
    !stopped &&
    generation === requestGeneration &&
    committed.value.snapshot.path === path &&
    event === "save" &&
    result?.status === "ok"
  ) {
    const href = result.data?.href;
    const destination =
      `/missions/${committed.value.route.params.mission_id}/spacecraft` +
      (committed.value.snapshot.spacecraft_page?.page === "profile_new" ? "/profiles" : "");
    if (href !== destination) throw new Error("Invalid spacecraft destination.");
    navigate(href);
  }
  return result;
}
async function activationDecision(input) {
  const path = committed.value.snapshot.path;
  const requestGeneration = generation;
  const token = committed.value.snapshot.activation_approvals?.token;
  const result = await request("host:activation", { path, token, input });
  if (!stopped && generation === requestGeneration && committed.value.snapshot.path === path) {
    if (result.page?.path !== path) throw new Error("Invalid activation response path.");
    committed.value = { ...committed.value, snapshot: result.page };
  }
  return result.result;
}
async function organizationPageAction(payload) {
  const path = committed.value.snapshot.path,
    requestGeneration = generation;
  const page = committed.value.snapshot.organization_module_page;
  if (pending.value || payload.id !== page?.id || payload.token !== page?.token)
    throw new Error("Inactive organization page.");
  const result = await request("host:organization-page", { ...payload, path });
  if (stopped || generation !== requestGeneration || committed.value.snapshot.path !== path)
    throw new Error("Inactive organization page response.");
  return result;
}
async function opsPageAction(payload) {
  const path = committed.value.snapshot.path,
    requestGeneration = generation;
  const page = committed.value.snapshot.ops_page;
  if (pending.value || payload.id !== page?.id || payload.token !== page?.token)
    throw new Error("Inactive Ops page.");
  const result = await request("host:ops-page", { ...payload, path });
  if (stopped || generation !== requestGeneration || committed.value.snapshot.path !== path)
    throw new Error("Inactive Ops page response.");
  return result;
}
async function opsPageRead(payload) {
  const path = committed.value.snapshot.path,
    requestGeneration = generation,
    page = committed.value.snapshot.ops_page;
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
    committed.value.snapshot.path !== path ||
    committed.value.snapshot.ops_page?.token !== payload.token
  )
    throw new Error("Inactive Ops page read response.");
  return result;
}
async function missionPageAction(payload) {
  const path = committed.value.snapshot.path,
    requestGeneration = generation;
  const page = committed.value.snapshot.mission_module_page;
  if (pending.value || payload.id !== page?.id || payload.token !== page?.token)
    throw new Error("Inactive mission page.");
  const result = await request("host:mission-page", { ...payload, path });
  if (stopped || generation !== requestGeneration || committed.value.snapshot.path !== path)
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
function updateDiagnosticsQuery(query) {
  const search = new URLSearchParams(query).toString();
  navigate(`/admin/runtime${search ? `?${search}` : ""}`);
}
// Routing is private to this host; descendants navigate through the host bridge.
// Installing a plugin here would redefine app-wide $route when this component remounts.
void router.replace(hostBrowserHistory.location).catch((error) => {
  if (!stopped) failure.value = error.message;
});
onMounted(() => {
  ownBrowserHistory(true);
  removeLinks = installHostNavigation(document, window.location, navigate);
  window.addEventListener("cadence:transport-reconnected", reconnect);
});
onBeforeUnmount(() => {
  stopped = true;
  generation++;
  for (const cancel of pendingRequests) cancel();
  removeLinks?.();
  ownBrowserHistory(false);
  window.removeEventListener("cadence:transport-reconnected", reconnect);
  router.listening = false;
  router.options.history.destroy();
});
</script>
<template>
  <ApplicationShell v-if="committed" :variant="variant" :context="context" managed-page>
    <HostPage
      :key="
        route.kind === 'administration_diagnostics' || route.kind === 'spacecraft'
          ? committed.route.path
          : committed.route.fullPath
      "
      :title="pageTitle"
      :breadcrumbs="pageBreadcrumbs"
      :workspace="variant === 'ops'"
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
        <AdministrationDiagnosticsPage
          v-else-if="route.kind === 'administration_diagnostics'"
          :snapshots="committed.snapshot.diagnostics ?? []"
          :interactions="{ updateQuery: updateDiagnosticsQuery }"
          :refreshing="refreshingDiagnostics"
          @refresh="refreshDiagnostics"
        />
        <ActivationApprovalsPage
          v-else-if="route.kind === 'activation_approvals'"
          :id="route.mountId"
          :snapshot="committed.snapshot.activation_approvals"
          :context="{
            organization_id: context.organization?.organization_id,
            mission_id: committed.route.params.mission_id,
          }"
          :execute="activationDecision"
          :refresh="reconnect"
          :navigating="pending"
        />
        <OrganizationModulePage
          v-else-if="route.kind === 'organization_module'"
          :id="route.mountId"
          :contribution-id="route.contribution"
          :snapshot="committed.snapshot.organization_module_page"
          :context="{
            organizationId: context.organization?.organization_id,
            resourceId: committed.route.params.provider_account_id,
          }"
          :execute="organizationPageAction"
          :navigate="navigate"
          :refresh="reconnect"
          :refreshing="pending"
        />
        <OpsModulePage
          v-else-if="route.kind === 'ops_module'"
          :id="route.mountId"
          :contribution-id="route.contribution"
          :snapshot="committed.snapshot.ops_page"
          :context="{
            organizationId: context.organization?.organization_id,
            missionId: committed.route.params.mission_id,
            resourceId: route.resourceParam
              ? committed.route.params[route.resourceParam]
              : undefined,
          }"
          :execute="opsPageAction"
          :query="opsPageRead"
          :navigate="navigate"
          :guard-navigation="guardNavigation"
          :refresh="reconnect"
          :refreshing="pending"
        />
        <MissionModulePage
          v-else-if="route.kind === 'mission_module'"
          :id="route.mountId"
          :contribution-id="route.contribution"
          :snapshot="committed.snapshot.mission_module_page"
          :execute="missionPageAction"
          :navigate="navigate"
          :context="{
            organizationId: context.organization?.organization_id,
            missionId: committed.route.params.mission_id,
            resourceId: route.resourceParam
              ? committed.route.params[route.resourceParam]
              : undefined,
          }"
          :refresh="reconnect"
          :refreshing="pending"
        />
        <SpacecraftModulePage
          v-else-if="route.kind === 'spacecraft_module'"
          :id="route.mountId"
          :contribution-id="route.contribution"
          :snapshot="committed.snapshot.spacecraft_module_page"
          :context="{
            organizationId: context.organization?.organization_id,
            missionId: committed.route.params.mission_id,
            spacecraftId: committed.route.params.spacecraft_id,
          }"
          :refresh="reconnect"
          :refreshing="pending"
        />
        <SpacecraftPage
          v-else-if="route.kind === 'spacecraft'"
          :id="route.mountId"
          :page="route.spacecraftPage"
          :class="route.viewClass"
          :snapshot="committed.snapshot.spacecraft_page"
          :execute="spacecraftAction"
          :navigating="pending"
          :navigate="navigate"
          :refresh="reconnect"
        />
        <NotificationsPage
          v-else-if="route.kind === 'notifications'"
          :key="context.user?.user_id"
          :snapshot="committed.snapshot.notifications_page"
          :user-id="context.user?.user_id"
          :act="notificationAction"
          :refresh="reconnect"
        />
        <WorkspaceLanding
          v-else-if="route.kind === 'ops_workspace' && route.workspacePage === 'landing'"
          :id="route.mountId"
          :model="committed.snapshot.ops_landing_page"
          :organization-id="context.organization?.organization_id"
          :mission-id="committed.route.params.mission_id"
        />
        <TimelinePage
          v-else-if="route.kind === 'ops_workspace' && route.workspacePage === 'timeline'"
          :id="route.mountId"
          :snapshot="committed.snapshot.timeline_page"
          :organization-id="context.organization?.organization_id"
          :mission-id="committed.route.params.mission_id"
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
          :organization-id="committed.route.params.org_id"
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
        <RoutedFederationSurface
          v-else
          :key="committed.route.fullPath"
          :id="route.mountId"
          :surface="surfaceProps"
          :view-class="route.viewClass"
          :navigate="navigate"
        />
      </div>
    </HostPage>
  </ApplicationShell>
  <p v-else-if="failure" id="host-navigation-error" role="alert">{{ failure }}</p>
  <p v-else role="status">Loading…</p>
</template>
