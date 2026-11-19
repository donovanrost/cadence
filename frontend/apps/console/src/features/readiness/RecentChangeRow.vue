<script setup lang="ts">
import { formatShort } from "@/ui";
import type { RecentChange } from "./api.ts";
import { revisionOf } from "./revisionOf.ts";

/** One R2 row: revision (linked when it's a change-set revision), time, sentence and actor. */
defineProps<{ change: RecentChange }>();
</script>

<template>
  <li
    class="grid grid-cols-[56px_96px_minmax(0,1fr)] items-baseline gap-2 border-t border-hairline px-4 py-2.5 first:border-t-0"
  >
    <RouterLink
      v-if="revisionOf(change.versionLabel)"
      :to="{ name: 'setup.revision', params: { revision: revisionOf(change.versionLabel) ?? '' } }"
      class="truncate font-mono text-[12px] text-readout hover:underline"
      >{{ change.versionLabel }}</RouterLink
    >
    <span v-else class="truncate font-mono text-[12px] text-text-2" :title="change.kind">{{
      change.versionLabel ?? change.kind
    }}</span>
    <time :datetime="change.at" class="font-mono text-xs text-text-4">{{
      formatShort(new Date(change.at))
    }}</time>
    <span class="text-md text-readout"
      >{{ change.summary
      }}<span v-if="change.actorName" class="text-text-3"> · {{ change.actorName }}</span></span
    >
  </li>
</template>
