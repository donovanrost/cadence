<script setup lang="ts" generic="T">
import { ref, watch } from "vue";
import { describeApiError } from "./http.ts";
import type { RemoteState } from "./remote-state.ts";
import { ApButton, ApCallout, ApEmptyState } from "@cadence/apogee-ui";

/**
 * Renders a RemoteState: loading line, failure callout with retry, or the default slot with the
 * value. Use inside a panel body so each region fails on its own.
 */
const props = defineProps<{
  state: RemoteState<T>;
  loadingLabel?: string;
  /** The 403 state's headline, e.g. "Org admins see this." (qa §6). */
  forbiddenText?: string;
  /**
   * a11y B6 (#276, ux): the load follows the person's own act (a typed search, a filter or day
   * change), so a failure is an alert. Without it, only a failure after this Retry is.
   */
  acted?: boolean | undefined;
}>();
const emit = defineEmits<{ retry: [] }>();
/** The person pressed Retry: a failure from here on is an alert, until a load succeeds. */
const retried = ref(false);
function retry() {
  retried.value = true;
  emit("retry");
}
watch(
  () => props.state.status,
  (status) => {
    if (status === "ready") retried.value = false;
  },
);
defineSlots<{ default: (props: { value: T; receivedAt: Date }) => unknown }>();
</script>

<template>
  <p
    v-if="state.status === 'loading'"
    role="status"
    class="m-0 px-4 py-3 font-mono text-sm text-text-4"
  >
    {{ loadingLabel ?? "Loading…" }}
  </p>
  <!-- A 403 is a state, not a failure: no Retry, which could never succeed (qa §6, lead). -->
  <ApEmptyState
    v-else-if="state.status === 'failed' && state.error.kind === 'forbidden'"
    state="off"
    :headline="forbiddenText ?? 'You don\'t have access to this.'"
  />
  <!-- B6 (#276, ux): a first load's failure is read politely; after the person acted, an alert. -->
  <ApCallout
    v-else-if="state.status === 'failed'"
    tone="caution"
    :role="retried || acted ? 'alert' : 'status'"
  >
    {{ describeApiError(state.error) }}
    <template #action><ApButton size="compact" @click="retry">Retry</ApButton></template>
  </ApCallout>
  <slot v-else :value="state.value" :received-at="state.receivedAt" />
</template>
