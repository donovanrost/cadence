<script setup lang="ts" generic="T">
import { describeApiError } from "./http.ts";
import type { RemoteState } from "./remote-state.ts";
import { ApButton, ApCallout } from "@cadence/apogee-ui";

/**
 * Renders a RemoteState: loading line, failure callout with retry, or the default slot with the
 * value. Use inside a panel body so each region fails on its own.
 */
defineProps<{ state: RemoteState<T>; loadingLabel?: string }>();
defineEmits<{ retry: [] }>();
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
  <ApCallout
    v-else-if="state.status === 'failed'"
    :tone="state.error.kind === 'forbidden' ? 'off' : 'caution'"
  >
    {{ describeApiError(state.error) }}
    <template #action><ApButton size="compact" @click="$emit('retry')">Retry</ApButton></template>
  </ApCallout>
  <slot v-else :value="state.value" :received-at="state.receivedAt" />
</template>
