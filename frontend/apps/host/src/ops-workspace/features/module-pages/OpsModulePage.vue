<script setup lang="ts">
import { computed, onBeforeUnmount, onErrorCaptured, ref, watch } from "vue";
import type {
  OpsPageContext,
  OpsPageAction,
  OpsPagePort,
  OpsPageNavigationPort,
  OpsPageReadRequest,
} from "@cadence/plugin-sdk/ops-pages";
import { opsPages } from "./contributions";
import { createOpsReadPort } from "./read-port";

const props = defineProps<{
  contributionId: string;
  snapshot: unknown;
  context: OpsPageContext;
  refresh: () => Promise<void>;
  refreshing?: boolean;
  execute?: (request: OpsPageAction) => Promise<unknown>;
  query?: (request: OpsPageReadRequest) => Promise<unknown>;
  navigate?: (href: string) => void;
  guardNavigation?: (guard: () => boolean) => () => void;
}>();
let disposed = false;
onBeforeUnmount(() => {
  disposed = true;
});
const crashed = ref(false);
const retrying = ref(false);
async function retry() {
  if (retrying.value || props.refreshing) return;
  retrying.value = true;
  try {
    await props.refresh();
  } catch {
    /* The unavailable page remains in place. */
  } finally {
    retrying.value = false;
  }
}
watch(
  () => [props.snapshot, props.context, props.contributionId],
  () => {
    crashed.value = false;
  },
);
onErrorCaptured(() => {
  crashed.value = true;
  return false;
});
const record = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === "object" && !Array.isArray(v);
const admitted = computed(() => {
  if (!Object.hasOwn(opsPages, props.contributionId)) return null;
  const registration = opsPages[props.contributionId],
    snapshot = props.snapshot;
  if (
    !record(snapshot) ||
    snapshot.id !== registration.id ||
    snapshot.slot !== registration.slot ||
    snapshot.version !== registration.version ||
    snapshot.status !== "ready" ||
    !record(snapshot.context)
  )
    return null;
  for (const key of [
    "organizationId",
    "missionId",
    ...(props.context.resourceId ? ["resourceId" as const] : []),
  ] as const) {
    if (
      typeof props.context[key] !== "string" ||
      !props.context[key] ||
      snapshot.context[key] !== props.context[key]
    )
      return null;
  }
  if (snapshot.context.resourceId !== props.context.resourceId) return null;
  try {
    const featureProps = registration.read(snapshot.data, props.context);
    const readContext = { ...props.context };
    const readToken = snapshot.token;
    const readPort = registration.query
      ? createOpsReadPort(
          registration.id,
          snapshot.token,
          readContext,
          () =>
            !disposed &&
            !props.refreshing &&
            props.contributionId === registration.id &&
            record(props.snapshot) &&
            props.snapshot.id === registration.id &&
            props.snapshot.slot === registration.slot &&
            props.snapshot.version === registration.version &&
            props.snapshot.status === "ready" &&
            props.snapshot.token === readToken &&
            record(props.snapshot.context) &&
            props.snapshot.context.organizationId === readContext.organizationId &&
            props.snapshot.context.missionId === readContext.missionId &&
            props.snapshot.context.resourceId === readContext.resourceId &&
            props.context.organizationId === readContext.organizationId &&
            props.context.missionId === readContext.missionId &&
            props.context.resourceId === readContext.resourceId,
          props.query,
        )
      : undefined;
    if (registration.query && !readPort) return null;
    let port: OpsPagePort | OpsPageNavigationPort | undefined;
    if (registration.actions) {
      const token = snapshot.token,
        organizationId = props.context.organizationId,
        missionId = props.context.missionId,
        resourceId = props.context.resourceId;
      if (
        typeof token !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(token) ||
        !props.execute ||
        !props.navigate
      )
        return null;
      const active = () =>
        !disposed &&
        props.contributionId === registration.id &&
        record(props.snapshot) &&
        props.snapshot.token === token &&
        props.snapshot.id === registration.id &&
        props.snapshot.status === "ready" &&
        props.snapshot.slot === registration.slot &&
        props.snapshot.version === registration.version &&
        record(props.snapshot.context) &&
        props.snapshot.context.organizationId === organizationId &&
        props.snapshot.context.missionId === missionId &&
        props.context.missionId === missionId &&
        props.context.resourceId === resourceId &&
        props.snapshot.context.resourceId === resourceId &&
        props.context.organizationId === organizationId;
      const current = () => active() && !props.refreshing;
      port = {
        async execute(event, input) {
          if (!current() || !registration.actions!.includes(event))
            throw new Error("Inactive Ops page action.");
          const result = await props.execute!({ id: registration.id, token, event, input });
          if (!current()) throw new Error("Inactive Ops page response.");
          return result;
        },
        navigate(href) {
          if (current()) props.navigate!(href);
        },
        ...(props.guardNavigation
          ? {
              guardNavigation(guard: () => boolean) {
                // Retained page guards span refreshes; only actions require an idle host.
                if (!active()) throw Error("Inactive Ops page navigation guard.");
                return props.guardNavigation!(() => !active() || guard());
              },
            }
          : {}),
      };
    } else if (registration.navigation) {
      if (!props.navigate) return null;
      const organizationId = props.context.organizationId,
        missionId = props.context.missionId,
        resourceId = props.context.resourceId,
        data = snapshot.data;
      const active = () =>
        !disposed &&
        props.snapshot === snapshot &&
        snapshot.id === registration.id &&
        snapshot.slot === registration.slot &&
        snapshot.version === registration.version &&
        snapshot.status === "ready" &&
        snapshot.data === data &&
        record(snapshot.context) &&
        snapshot.context.organizationId === organizationId &&
        snapshot.context.missionId === missionId &&
        snapshot.context.resourceId === resourceId &&
        props.contributionId === registration.id &&
        props.context.organizationId === organizationId &&
        props.context.missionId === missionId &&
        props.context.resourceId === resourceId;
      port = {
        navigate(href) {
          if (active() && !props.refreshing) props.navigate!(href);
        },
        ...(props.guardNavigation
          ? {
              guardNavigation(guard: () => boolean) {
                if (!active()) throw Error("Inactive Ops page navigation guard.");
                return props.guardNavigation!(() => !active() || guard());
              },
            }
          : {}),
      };
    }
    return {
      component: registration.component,
      key: typeof snapshot.token === "string" ? snapshot.token : registration.id,
      props: {
        ...featureProps,
        ...(port ? { port } : {}),
        ...(readPort ? { readPort } : {}),
        refresh: props.refresh,
      },
    };
  } catch {
    return null;
  }
});
</script>
<template>
  <section id="ops-module-page">
    <div
      v-if="crashed || !admitted"
      id="ops-module-unavailable"
      role="alert"
      class="card border border-warning/40 bg-base-200 p-6"
    >
      <p>This Ops feature is unavailable. The current Cadence page remains available.</p>
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
