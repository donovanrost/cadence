<script setup lang="ts">
import { formatShort, ApEmptyState, ApPanel } from "@/ui";
import type { RecentChange } from "./api.ts";

/** R2 (ux U2): replaces the canvas's mission revisions until change sets exist. */
defineProps<{ changes: readonly RecentChange[] }>();
</script>

<template>
  <ApPanel index="R2" title="Recent changes" flush>
    <template #meta>
      <RouterLink :to="{ name: 'org.audit' }" class="text-text-3 no-underline hover:text-readout"
        >Audit log →</RouterLink
      >
    </template>
    <ApEmptyState
      v-if="changes.length === 0"
      headline="No changes recorded yet"
      sentence="Spacecraft, profile, catalog and app changes appear here as they're made."
    />
    <ol v-else class="m-0 list-none p-0">
      <li
        v-for="change in changes.slice(0, 5)"
        :key="`${change.at}-${change.kind}-${change.summary}`"
        class="grid grid-cols-[56px_96px_minmax(0,1fr)] items-baseline gap-2 border-t border-hairline px-4 py-2.5 first:border-t-0"
      >
        <span
          class="truncate font-mono text-[12px] text-text-2"
          :title="change.versionLabel ?? change.kind"
          >{{ change.versionLabel ?? change.kind }}</span
        >
        <time :datetime="change.at" class="font-mono text-xs text-text-4">{{
          formatShort(new Date(change.at))
        }}</time>
        <span class="text-md text-readout"
          >{{ change.summary
          }}<span v-if="change.actorName" class="text-text-3"> · {{ change.actorName }}</span></span
        >
      </li>
    </ol>
  </ApPanel>
</template>
