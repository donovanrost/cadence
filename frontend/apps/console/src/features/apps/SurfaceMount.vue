<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, shallowRef, watch, type Component } from "vue";
import { onBeforeRouteLeave, useRoute, useRouter } from "vue-router";
import {
  fullPageSurfaceProps,
  type FullPageSurfaceProps,
  type HostSessionDescriptor,
} from "@cadence/plugin-sdk";
import { createHttpHostBridge, loadFederatedApplication } from "@cadence/plugin-sdk/host";
import { ApButton, ApCallout } from "@/ui";
import type { SurfaceHost } from "./host.ts";
import { lostText, repinningBridge, type RepinningBridge } from "./hostBridge.ts";
import { surfaceLink, surfaceParams } from "./surfaces.ts";
import { saveOutcome, type SaveOutcome } from "./saveOutcome.ts";

/**
 * L9 surface body (ux AppSurfaces.md): loads the server-approved federated module, gives it a
 * re-pinning host bridge (one scope per session, api), and passes every action receipt through the
 * app's save-outcome adapter (the seam, DECISIONS #77). One surface is mounted at a time.
 */
const props = defineProps<{
  host: SurfaceHost;
  appName: string;
  /** Re-requests the `/host` read to re-pin the app-host session. */
  repin: () => Promise<HostSessionDescriptor | null>;
}>();
const emit = defineEmits<{ outcome: [outcome: SaveOutcome] }>();
const router = useRouter();
const route = useRoute();
/**
 * ux U42 deep links: the URL's query, limited to the keys this app's surface query accepts, goes to
 * the server as the host-captured params (plugin-sdk: a surface never sends its own).
 */
const params = computed(() => (app ? surfaceParams(app.applicationKey, route.query) : {}));
const app = props.host.catalog.applications[0];
const surface = shallowRef<{ component: Component; props: FullPageSurfaceProps } | null>(null);
const failure = ref<string | null>(null);
const lost = ref(false);
/** The surface's own report (plugin-sdk HostBridge.report); surfaces that don't report never block. */
const dirty = ref(false);
onBeforeRouteLeave(() =>
  dirty.value
    ? window.confirm("Leave this page? Changes you haven't saved here will be lost.")
    : true,
);
let bridge: RepinningBridge | null = null;

/**
 * Console paths stay in the SPA (router base /console/). So do the surface's own links (its legacy
 * `/missions/:m/applications/…` paths): they re-open this route with their query. Anything else is a
 * full navigation.
 */
function navigate(href: string) {
  if (href.startsWith("/console/")) return void router.push(href.replace(/^\/console/, ""));
  const own = surfaceLink(href, props.host.catalog.session.context.missionId ?? "");
  if (!own) return window.location.assign(href);
  const surfaceParam = { appKey: own.appKey, surface: own.surface };
  void router.push(
    route.name === "setup.spacecraft.app"
      ? { name: route.name, params: { ...route.params, ...surfaceParam }, query: own.query }
      : { name: "setup.app", params: surfaceParam, query: own.query },
  );
}

async function load() {
  if (!app) return void (failure.value = "the server sent no surface.");
  failure.value = null;
  lost.value = false;
  surface.value = null;
  bridge?.dispose();
  try {
    const module = await loadFederatedApplication(app);
    bridge = repinningBridge({
      session: props.host.catalog.session,
      create: (session) =>
        createHttpHostBridge(session, app, { navigate, queryParams: params.value }),
      repin: props.repin,
      navigate,
      onReceipt: (actionId) => {
        const outcome = saveOutcome(app.applicationKey, actionId);
        if (outcome) emit("outcome", outcome);
      },
      onLost: () => (lost.value = true),
      onReport: (state) => {
        if (state.dirty !== undefined) dirty.value = state.dirty;
      },
    });
    surface.value = {
      component: module.default,
      props: fullPageSurfaceProps(app, props.host.catalog.session.context, bridge.bridge),
    };
  } catch (cause) {
    failure.value = cause instanceof Error ? cause.message : "it didn't answer.";
  }
}
// A new selection or page (a deep link, or the surface's own link) re-queries with the new params.
watch(
  () => JSON.stringify(params.value),
  () => void load(),
);
// L19b (api eecfc73d5): the session keeps its 16 latest scopes, so a tab regaining focus needn't
// re-pin; a mismatch (a scope pushed out) still re-pins and retries once in the bridge.
onMounted(() => void load());
onBeforeUnmount(() => bridge?.dispose());
</script>

<template>
  <template v-if="failure">
    <ApCallout tone="crit">
      This app's page couldn't load: {{ failure }}
      <template #action><ApButton size="compact" @click="load">Try again</ApButton></template>
    </ApCallout>
    <p class="m-0 text-sm text-text-3">{{ appName }} v{{ app?.applicationVersion }}</p>
  </template>
  <ApCallout v-if="lost && !failure" tone="caution">{{ lostText(dirty) }}</ApCallout>
  <p v-if="!failure && !surface" class="m-0 font-mono text-xs text-text-3 uppercase">
    Loading {{ appName }}…
  </p>
  <component :is="surface.component" v-if="!failure && surface" v-bind="surface.props" />
</template>
