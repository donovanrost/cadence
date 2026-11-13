<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, shallowRef, type Component } from "vue";
import { onBeforeRouteLeave, useRouter } from "vue-router";
import {
  fullPageSurfaceProps,
  type FullPageSurfaceProps,
  type HostSessionDescriptor,
} from "@cadence/plugin-sdk";
import { createHttpHostBridge, loadFederatedApplication } from "@cadence/plugin-sdk/host";
import { ApButton, ApCallout } from "@/ui";
import type { SurfaceHost } from "./host.ts";
import { lostText, repinningBridge, type RepinningBridge } from "./hostBridge.ts";
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

/** Console paths stay in the SPA (router base /console/); anything else is a full navigation. */
function navigate(href: string) {
  if (href.startsWith("/console/")) void router.push(href.replace(/^\/console/, ""));
  else window.location.assign(href);
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
      create: (session) => createHttpHostBridge(session, app, { navigate }),
      repin: props.repin,
      navigate,
      onReceipt: (actionId, receipt) => {
        const outcome = saveOutcome(app.applicationKey, actionId, receipt);
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
/** Another tab may have taken the session while this one was hidden: re-pin on return (lead). */
function onVisible() {
  if (document.visibilityState === "visible" && bridge)
    void bridge.repinNow().then((ok) => (lost.value = !ok));
}
onMounted(() => {
  void load();
  document.addEventListener("visibilitychange", onVisible);
});
onBeforeUnmount(() => {
  document.removeEventListener("visibilitychange", onVisible);
  bridge?.dispose();
});
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
