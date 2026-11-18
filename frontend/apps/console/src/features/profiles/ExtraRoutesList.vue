<script setup lang="ts">
import type { ExtraRouteRow } from "./detail.ts";
import { extraRouteLine } from "./overrides.ts";

/**
 * U79 P3: the spacecraft's own extra routes, as override rows. Each links to that spacecraft's
 * routing, where they're added, edited and removed; P3 doesn't change them.
 */
defineProps<{ routes: readonly ExtraRouteRow[] }>();
</script>

<template>
  <ul class="m-0 list-none border-t border-hairline p-0" aria-label="Extra routes">
    <li
      v-for="r in routes"
      :key="r.route_id"
      class="grid grid-cols-[150px_minmax(0,1fr)] items-center gap-3 border-t border-hairline px-4 py-2.5 first:border-t-0 max-md:grid-cols-1"
    >
      <RouterLink
        :to="{ name: 'setup.spacecraft.one', params: { spacecraftId: r.spacecraft.id } }"
        class="font-mono text-readout no-underline hover:underline max-md:hit-44"
        >{{ r.spacecraft.name ?? "Unknown spacecraft" }}</RouterLink
      >
      <span class="text-md text-readout">{{ extraRouteLine(r) }}</span>
    </li>
  </ul>
</template>
