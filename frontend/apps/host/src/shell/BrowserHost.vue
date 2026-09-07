<script setup>
import { computed, getCurrentInstance, onBeforeUnmount, onMounted, shallowRef, watch } from "vue";
import { useLiveVue } from "live_vue";
import HostPage from "./HostPage.vue";
import ApplicationShell from "./ApplicationShell.vue";
import MissionApplicationManagement from "./MissionApplicationManagement.vue";
import SpacecraftApplicationManagement from "./SpacecraftApplicationManagement.vue";
import RoutedFederationSurface from "./RoutedFederationSurface.vue";
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

router.beforeEach(async (to) => {
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
  if (navigationFailure) return;
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
const management = computed(() =>
  route.value?.scope === "spacecraft"
    ? SpacecraftApplicationManagement
    : MissionApplicationManagement,
);
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
  try {
    const snapshot = await request("host:manage", { ...payload, event, path });
    if (committed.value.snapshot.path === path) committed.value = { ...committed.value, snapshot };
  } catch (error) {
    failure.value = error.message;
  }
}
async function reconnect() {
  if (!committed.value) return;
  try {
    const path = committed.value.snapshot.path;
    const snapshot = await request("host:context", { path });
    if (committed.value.snapshot.path === path) committed.value = { ...committed.value, snapshot };
  } catch (error) {
    failure.value = error.message;
  }
}
getCurrentInstance().appContext.app.use(router);
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
  // Removing the router's listener leaves the shared browser history available
  // for another host mounted after a native Phoenix navigation.
  router.listening = false;
});
</script>
<template>
  <ApplicationShell v-if="committed" :variant="variant" :context="context" managed-page>
    <HostPage
      :key="committed.route.fullPath"
      :title="pageTitle"
      :breadcrumbs="pageBreadcrumbs"
      :workspace="variant === 'ops'"
    >
      <p v-if="failure" id="host-navigation-error" role="alert">{{ failure }}</p>
      <div :aria-busy="pending" :data-host-path="committed.snapshot.path">
        <div v-if="route.kind === 'application_management'" :id="route.mountId" class="contents">
          <component
            :is="management"
            v-if="committed.snapshot.presentation"
            :presentation="committed.snapshot.presentation"
            @install="manage('install', $event)"
            @disable="manage('disable', $event)"
            @uninstall="manage('uninstall', $event)"
          />
          <p v-if="committed.snapshot.error" id="application-management-error" role="alert">
            {{ committed.snapshot.error }}
          </p>
        </div>
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
