<script setup lang="ts">
import { formatShort, ApEmptyState, ApPanel } from "@/ui";
import type { RecentChange } from "./api.ts";

/** R2 (ux U2, api): the last 5 applied config revisions; null means revisions couldn't be read. */
defineProps<{ changes: readonly RecentChange[] | null }>();
/** "r3" → 3, for the revision page; anything else stays plain text. */
const revisionOf = (label: string | null) =>
  label && /^r\d+$/.test(label) ? label.slice(1) : null;
</script>

<template>
  <ApPanel index="R2" title="Recent changes" flush>
    <template #meta>
      <RouterLink
        :to="{ name: 'setup.revisions' }"
        class="text-text-3 no-underline hover:text-readout max-md:hit-44"
        >All revisions →</RouterLink
      >
    </template>
    <ApEmptyState
      v-if="changes === null"
      state="off"
      headline="Recent changes couldn't be read"
      sentence="The revisions list is still on the Revisions page."
    />
    <ApEmptyState
      v-else-if="changes.length === 0"
      headline="Nothing applied yet"
      sentence="Applied change sets and rollbacks appear here."
    />
    <ol v-else class="m-0 list-none p-0">
      <li
        v-for="change in changes.slice(0, 5)"
        :key="`${change.at}-${change.kind}-${change.summary}`"
        class="grid grid-cols-[56px_96px_minmax(0,1fr)] items-baseline gap-2 border-t border-hairline px-4 py-2.5 first:border-t-0"
      >
        <RouterLink
          v-if="revisionOf(change.versionLabel)"
          :to="{ name: 'setup.revision', params: { revision: revisionOf(change.versionLabel) } }"
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
    </ol>
  </ApPanel>
</template>
