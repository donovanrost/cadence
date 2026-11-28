<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, shallowRef, watch } from "vue";
import type { RouteLocationNormalized } from "vue-router";
import { isNavigationFailure, NavigationFailureType } from "vue-router";
import type {
  OpsPageNavigationResult,
  OpsPageUpdateSubscription,
} from "@cadence/plugin-sdk/ops-pages";
import { readHostSnapshot, errorMessage, type HostSnapshot } from "./host-snapshot";
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

const TimelinePage = lazyHostPage(
  "TimelinePage",
  () => import("../ops-workspace/features/timeline/TimelinePage.vue"),
);
const OpsModulePage = lazyHostPage(
  "OpsModulePage",
  () => import("../ops-workspace/features/module-pages/OpsModulePage.vue"),
);

const props = defineProps<{ snapshot: unknown }>();
const initialSnapshot = readHostSnapshot(props.snapshot);
const live = useLiveVue();
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
const failure = shallowRef<string | null>(null);
const pending = shallowRef(false);
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
  if (leaveGuard && !leaveGuard()) event.preventDefault();
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
      :key="committed.route.fullPath"
      :title="pageTitle"
      :breadcrumbs="pageBreadcrumbs"
      :workspace="variant === 'ops'"
      :heading="pageHeading"
      :route="route.path"
      :section="pageSection"
    >
      <p v-if="failure" id="host-navigation-error" role="alert">{{ failure }}</p>
      <div :aria-busy="pending" :data-host-path="committed.snapshot.path">
        <OpsModulePage
          v-if="route.kind === 'ops_module' && missionContext"
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
        <p v-else id="host-route-unavailable" role="alert">This page is unavailable.</p>
      </div>
    </HostPage>
  </ApplicationShell>
  <p v-else-if="failure" id="host-navigation-error" role="alert">{{ failure }}</p>
  <p v-else role="status">Loading…</p>
</template>
