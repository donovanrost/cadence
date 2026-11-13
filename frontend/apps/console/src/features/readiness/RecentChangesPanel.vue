<script setup lang="ts">
import { computed } from "vue";
import { ApEmptyState, ApPanel } from "@/ui";
import type { RecentChange } from "./api.ts";
import RecentChangeRow from "./RecentChangeRow.vue";
import { compareSpan } from "./revisionOf.ts";

/** R2 (ux U2, api): the last 5 applied config revisions; null means revisions couldn't be read. */
const props = defineProps<{ changes: readonly RecentChange[] | null }>();
const compare = computed(() =>
  compareSpan((props.changes ?? []).slice(0, 5).map((c) => c.versionLabel)),
);
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
      <RecentChangeRow
        v-for="change in changes.slice(0, 5)"
        :key="`${change.at}-${change.kind}-${change.summary}`"
        :change="change"
      />
    </ol>
    <RouterLink
      v-if="compare"
      :to="{ name: 'setup.revisions.compare', params: compare }"
      class="block border-t border-hairline px-4 py-2.5 font-mono text-xs text-text-3 no-underline hover:text-readout"
      >Compare r{{ compare.from }} ↔ r{{ compare.to }} →</RouterLink
    >
  </ApPanel>
</template>
