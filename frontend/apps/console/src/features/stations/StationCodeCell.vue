<script setup lang="ts">
import type { Station } from "./api.ts";

/**
 * U25 code cell for a station with no confirmed code: the server's suggestion dimmed, with
 * "Suggested · Confirm" for editors (viewers get "—", the suggestion only in the title).
 */
defineProps<{ station: Station; canEdit: boolean; staged: boolean; busy: boolean }>();
defineEmits<{ confirm: [] }>();
</script>

<template>
  <span
    v-if="!canEdit"
    class="text-text-4"
    :title="station.suggested_code ? `Suggested: ${station.suggested_code}` : undefined"
    >—</span
  >
  <span v-else-if="staged" class="font-sans text-sm text-text-3"
    ><span class="font-mono text-text-4">{{ station.suggested_code }}</span> · Staged ·
    <RouterLink :to="{ name: 'setup.changes' }" class="text-readout hover:underline"
      >Review</RouterLink
    ></span
  >
  <span v-else-if="station.suggested_code" class="inline-flex items-baseline gap-1.5"
    ><span class="text-text-4">{{ station.suggested_code }}</span
    ><span class="font-sans text-sm text-text-3"
      >Suggested ·
      <button
        type="button"
        class="cursor-pointer border-0 bg-transparent p-0 text-readout hover:underline disabled:cursor-wait max-md:hit-44"
        :disabled="busy"
        @click="$emit('confirm')"
      >
        {{ busy ? "Staging…" : "Confirm" }}
      </button></span
    ></span
  >
  <RouterLink
    v-else
    :to="{ name: 'setup.stations', params: { stationId: station.id } }"
    class="font-sans text-sm text-text-3 no-underline hover:text-readout max-md:hit-44"
    >Not set · Add code</RouterLink
  >
</template>
