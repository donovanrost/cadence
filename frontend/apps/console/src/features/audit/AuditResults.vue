<script setup lang="ts">
import type { Unshown } from "@/api";
import { UnshownCallout } from "@/features/now/index.ts";
import { ApButton, ApCallout, ApEmptyState, ApPanel, formatCount } from "@/ui";
import AuditTable from "./AuditTable.vue";
import { listWords, sourcePhrase, type AuditEvent, type AuditPage } from "./api.ts";

/** Audit log results: missing-sources note, the table, and Load older (cursor paging). */
const props = defineProps<{
  /** Every page loaded so far, in order. */
  events: readonly AuditEvent[];
  /** The first page's sources (the query's, so the same on every page). */
  sources: AuditPage["sources"];
  /** U86: the events every loaded page left out, for the line above the table. */
  unshown: readonly Unshown[];
  hasMore: boolean;
  loading: boolean;
  failed: boolean;
  span: string;
}>();
defineEmits<{ older: [] }>();
const words = (which: "included" | "missing") => listWords(props.sources[which].map(sourcePhrase));
const capitalized = (text: string) => text.charAt(0).toUpperCase() + text.slice(1);
</script>

<template>
  <ApCallout v-if="sources.missing.length > 0" tone="info">
    Showing {{ words("included") }}. {{ capitalized(words("missing")) }} aren't in the audit log
    yet.
  </ApCallout>
  <ApPanel index="L1" title="Audit" flush>
    <UnshownCallout :unshown="unshown" noun="event" />
    <ApEmptyState
      v-if="events.length === 0 && unshown.length === 0"
      :headline="`No audited actions in the last ${span}`"
    />
    <AuditTable v-else-if="events.length > 0" :events="events">
      <template #footer>
        <div
          v-if="hasMore || failed || events.length > 0"
          class="flex items-center gap-3 border-t border-hairline px-4 py-2.5 text-sm text-text-3"
        >
          <span>{{ formatCount(events.length) }} shown</span>
          <ApButton
            size="compact"
            :disabled="loading || !hasMore"
            :disabled-reason="loading ? 'Loading…' : 'No older events'"
            @click="$emit('older')"
            >Load older</ApButton
          >
          <!-- #244 (B6): it answers the person's own click, so an alert (ca-ux, as #410), always
            mounted and in the tree (no display:none, ux) so it's announced; usePagedQuery clears
            moreError as Load older starts, so a repeat failure is said again. -->
          <span role="alert" class="text-caution-text">{{
            failed ? "Older events couldn't load. Try Load older again." : ""
          }}</span>
        </div>
      </template>
    </AuditTable>
  </ApPanel>
</template>
