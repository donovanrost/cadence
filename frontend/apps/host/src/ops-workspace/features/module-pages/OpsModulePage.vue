<script setup lang="ts">
import { computed } from "vue";
import { useLazyPage } from "../../../shell/module-pages/lazy-pages";
import type {
  OpsPageContext,
  OpsPageAction,
  OpsPagePort,
  OpsPageNavigationPort,
  OpsPageReadRequest,
  SettledOpsPageNavigationPort,
} from "@cadence/plugin-sdk/ops-pages";
import { opsPages } from "./contributions";
import { createOpsReadPort } from "./read-port";
import { capturePage, createPageActionPort } from "../../../shell/module-pages/page-admission";
import { usePageBoundary } from "../../../shell/module-pages/use-page-boundary";

const props = defineProps<{
  contributionId: string;
  snapshot: unknown;
  context: OpsPageContext;
  refresh: () => Promise<void>;
  refreshing?: boolean;
  execute?: (request: OpsPageAction) => Promise<unknown>;
  query?: (request: OpsPageReadRequest) => Promise<unknown>;
  navigate?: (href: string) => void;
  navigateSettled?: SettledOpsPageNavigationPort["navigate"];
  guardNavigation?: (guard: () => boolean) => () => void;
}>();
const boundary = usePageBoundary(props, "ops.page");
const { crashed, retrying, diagnosticId } = boundary;
const loaded = useLazyPage(
  () => props.contributionId,
  opsPages,
  (cause) => boundary.report("load", cause),
);
const loading = computed(() => loaded.state.value.kind === "loading");
async function retry() {
  await boundary.retry();
  loaded.reload();
}
const admitted = computed(() => {
  try {
    const state = loaded.state.value;
    if (state.kind !== "ready") return null;
    const registration = state.value;
    const captured = capturePage(
      props,
      registration,
      ["organizationId", "missionId"],
      boundary.alive,
    );
    if (registration.guardNavigation && !props.guardNavigation)
      throw Error("Missing Ops navigation guard.");
    const featureProps = registration.read(captured.data, props.context);
    const readPort = registration.query
      ? createOpsReadPort(
          registration.id,
          captured.token,
          props.context,
          captured.current,
          props.query,
        )
      : undefined;
    if (registration.query && !readPort) throw Error("Missing Ops read capability.");
    let port: OpsPagePort | OpsPageNavigationPort | undefined;
    let active = captured.active;
    if (registration.actions) {
      port = createPageActionPort(
        { ...registration, actions: registration.actions },
        captured.token,
        captured.current,
        props,
        "Ops page",
      );
    } else if (registration.navigation) {
      const snapshot = props.snapshot;
      active = () => captured.active() && props.snapshot === snapshot;
      if (registration.navigation === "settled") {
        if (!props.navigateSettled) throw Error("Missing completed navigation capability.");
        port = {
          navigate(href: string) {
            return active() && !props.refreshing && props.navigateSettled
              ? props.navigateSettled(href)
              : Promise.resolve("cancelled");
          },
        };
      } else {
        if (!props.navigate) throw Error("Missing Ops navigation capability.");
        port = {
          navigate(href: string) {
            if (active() && !props.refreshing) props.navigate?.(href);
          },
        };
      }
    }
    if (port && props.guardNavigation) {
      port = {
        ...port,
        guardNavigation(guard: () => boolean) {
          if (!active() || !props.guardNavigation)
            throw Error("Inactive Ops page navigation guard.");
          return props.guardNavigation(() => !active() || guard());
        },
      };
    }
    return {
      component: registration.component,
      key: typeof captured.token === "string" ? captured.token : registration.id,
      props: {
        ...featureProps,
        ...(port ? { port } : {}),
        ...(readPort ? { readPort } : {}),
        refresh: props.refresh,
      },
    };
  } catch (cause) {
    boundary.report("admission", cause);
    return null;
  }
});
</script>
<template>
  <section id="ops-module-page">
    <div v-if="loading" id="ops-module-loading" role="status" class="p-6">Loading feature…</div>
    <div
      v-else-if="crashed || !admitted"
      id="ops-module-unavailable"
      role="alert"
      class="card border border-warning/40 bg-base-200 p-6"
    >
      <p>This Ops feature is unavailable. The current Cadence page remains available.</p>
      <p v-if="diagnosticId" class="mt-2 text-xs">Reference: {{ diagnosticId }}</p>
      <button
        id="ops-module-retry"
        type="button"
        class="btn btn-sm mt-4"
        :disabled="refreshing || retrying"
        @click="retry"
      >
        Retry
      </button>
    </div>
    <component v-else :is="admitted.component" :key="admitted.key" v-bind="admitted.props" />
  </section>
</template>
