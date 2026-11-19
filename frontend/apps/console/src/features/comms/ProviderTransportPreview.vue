<script setup lang="ts">
import type { ProviderOptions } from "./provider-options.ts";

/**
 * What Cadence will use for a provider-managed transport: derive/3's result as api renders it
 * (summary rows, then the full configuration). Read-only: the kind derives these on apply.
 */
defineProps<{ preview: NonNullable<ProviderOptions["preview"]> }>();
</script>

<template>
  <section
    class="flex flex-col gap-2 border border-hairline px-4 py-3"
    aria-label="Settings from the delivery profile"
  >
    <span class="ap-label">Settings from the delivery profile</span>
    <dl class="m-0 grid grid-cols-[max-content_minmax(0,1fr)] gap-x-4 gap-y-1">
      <template v-for="row in preview.configuration" :key="row.label">
        <dt class="text-sm text-text-2">{{ row.label }}</dt>
        <dd class="m-0 font-mono text-sm text-readout">{{ row.value }}</dd>
      </template>
    </dl>
    <p class="m-0 text-sm text-text-3">
      Cadence takes these from the provider (version {{ preview.provider_version }}) when the change
      is applied.
    </p>
  </section>
</template>
