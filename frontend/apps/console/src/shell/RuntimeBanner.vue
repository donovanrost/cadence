<script setup lang="ts">
import { ApCallout } from "@/ui";
import type { RuntimeBanner } from "./runtime-banner.ts";

/**
 * U38 strip under the top bar on every mission page: one line, truncated with `Details` kept
 * visible, not dismissable. `Details` goes to the mission_runtime row on Now.
 */
defineProps<{ banner: NonNullable<RuntimeBanner> }>();
</script>

<template>
  <ApCallout :tone="banner.tone" class="flex-none">
    <span class="block truncate" :title="banner.text">{{ banner.text }}</span>
    <template v-if="banner.tone === 'crit'" #action>
      <RouterLink
        :to="{ name: 'ops.now' }"
        class="max-md:hit-44 flex-none text-readout underline hover:text-bright"
        >Details</RouterLink
      >
    </template>
  </ApCallout>
</template>
