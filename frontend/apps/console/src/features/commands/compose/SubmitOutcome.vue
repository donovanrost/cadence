<script setup lang="ts">
import { ApButton, ApCallout } from "@/ui";
import type { SubmitState } from "./useSubmit.ts";

/** ux U20: rejected = nothing changed, with the server's reason; unclear = check, not retry. */
defineProps<{ state: SubmitState }>();
defineEmits<{ check: [] }>();
</script>

<template>
  <ApCallout v-if="state.status === 'rejected'" tone="crit">
    Not sent. Nothing changed: {{ state.message }}
    <template v-if="state.stale"> The checks ran again; review them and send.</template>
  </ApCallout>
  <ApCallout v-else-if="state.status === 'unclear'" tone="caution">
    It's unclear whether this was sent ({{ state.message }}). Check before sending again.
    <template #action><ApButton size="compact" @click="$emit('check')">Check</ApButton></template>
  </ApCallout>
  <p v-else-if="state.status === 'checking'" class="m-0 font-mono text-sm text-text-3 uppercase">
    Checking whether it was sent…
  </p>
</template>
