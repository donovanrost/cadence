<script setup lang="ts">
import { formatCount } from "@/ui";
import type { AppHold } from "./holds.ts";

/**
 * U63: a HOLD that needs an app installed first links to that app's page in Setup › Apps (where
 * install happens). It names the first few spacecraft the server sent and says how many more
 * (#796): no fleet read to name them.
 */
defineProps<{ holds: readonly AppHold[] }>();
const more = (h: AppHold) => h.spacecraftCount - h.spacecraftSample.length;
</script>

<template>
  <div
    v-for="h in holds"
    :key="h.appKey"
    class="flex flex-col gap-1 border-t border-hairline px-4 py-2.5 text-sm text-text-2"
  >
    <RouterLink
      :to="{ name: 'setup.app', params: { appKey: h.appKey } }"
      class="text-primary no-underline hover:underline"
      >Open Setup › Apps{{ h.appName ? ` (${h.appName})` : "" }}</RouterLink
    >
    <p v-if="h.spacecraftSample.length > 0" class="m-0 font-mono text-xs text-text-2">
      {{ h.spacecraftSample.map((s) => s.name).join(", ")
      }}{{ more(h) > 0 ? ` and ${formatCount(more(h))} more` : "" }}
    </p>
  </div>
</template>
