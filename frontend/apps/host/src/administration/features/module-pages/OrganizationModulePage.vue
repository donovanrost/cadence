<script setup lang="ts">
import { computed, onBeforeUnmount, onErrorCaptured, ref, watch } from "vue";
import type {
  OrganizationPageContext,
  OrganizationPageAction,
  OrganizationPagePort,
} from "@cadence/plugin-sdk/organization-pages";
import { organizationModulePages } from "./contributions";

const props = defineProps<{
  contributionId: string;
  snapshot: unknown;
  context: OrganizationPageContext;
  refresh: () => Promise<void>;
  refreshing?: boolean;
  execute?: (request: OrganizationPageAction) => Promise<unknown>;
  navigate?: (href: string) => void;
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
  if (!Object.hasOwn(organizationModulePages, props.contributionId)) return null;
  const registration = organizationModulePages[props.contributionId],
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
    ...(props.context.resourceId ? ["resourceId" as const] : []),
  ] as const) {
    if (
      typeof props.context[key] !== "string" ||
      !props.context[key] ||
      snapshot.context[key] !== props.context[key]
    )
      return null;
  }
  try {
    const featureProps = registration.read(snapshot.data, props.context);
    let port: OrganizationPagePort | undefined;
    if (registration.actions) {
      const token = snapshot.token,
        organizationId = props.context.organizationId,
        resourceId = props.context.resourceId;
      if (
        typeof token !== "string" ||
        !/^[0-9a-f-]{36}$/.test(token) ||
        !props.execute ||
        !props.navigate
      )
        return null;
      const current = () =>
        !disposed &&
        !props.refreshing &&
        record(props.snapshot) &&
        props.snapshot.token === token &&
        props.snapshot.id === registration.id &&
        props.snapshot.status === "ready" &&
        props.snapshot.slot === registration.slot &&
        props.snapshot.version === registration.version &&
        record(props.snapshot.context) &&
        props.snapshot.context.organizationId === organizationId &&
        props.context.resourceId === resourceId &&
        props.snapshot.context.resourceId === resourceId &&
        props.context.organizationId === organizationId;
      port = {
        async execute(event, input) {
          if (!current() || !registration.actions!.includes(event))
            throw new Error("Inactive organization page action.");
          const result = await props.execute!({ id: registration.id, token, event, input });
          if (!current()) throw new Error("Inactive organization page response.");
          return result;
        },
        navigate(href) {
          if (current()) props.navigate!(href);
        },
      };
    }
    return {
      component: registration.component,
      key: typeof snapshot.token === "string" ? snapshot.token : registration.id,
      props: { ...featureProps, ...(port ? { port } : {}) },
    };
  } catch {
    return null;
  }
});
</script>
<template>
  <section id="organization-module-page">
    <div
      v-if="crashed || !admitted"
      id="organization-module-unavailable"
      role="alert"
      class="card border border-warning/40 bg-base-200 p-6"
    >
      <p>This organization feature is unavailable. The current Cadence page remains available.</p>
      <button
        id="organization-module-retry"
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
