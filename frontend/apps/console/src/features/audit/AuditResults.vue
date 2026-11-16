<script setup lang="ts">
import { ApButton, ApCallout, ApEmptyState, ApPanel, formatCount } from "@/ui";
import AuditTable from "./AuditTable.vue";
import { listWords, sourcePhrase, type AuditEvent, type AuditPage } from "./api.ts";

/** Audit log results: missing-sources note, the table, and Load older (cursor paging). */
defineProps<{
  page: AuditPage;
  older: readonly AuditEvent[];
  hasMore: boolean;
  loading: boolean;
  failed: boolean;
  span: string;
}>();
defineEmits<{ older: [] }>();
const words = (p: AuditPage, which: "included" | "missing") =>
  listWords(p.sources[which].map(sourcePhrase));
const capitalized = (text: string) => text.charAt(0).toUpperCase() + text.slice(1);
</script>

<template>
  <ApCallout v-if="page.sources.missing.length > 0" tone="info">
    Showing {{ words(page, "included") }}. {{ capitalized(words(page, "missing")) }} aren't in the
    audit log yet.
  </ApCallout>
  <ApPanel index="L1" title="Audit" flush>
    <ApEmptyState
      v-if="page.events.length === 0"
      :headline="`No audited actions in the last ${span}`"
    />
    <AuditTable v-else :events="[...page.events, ...older]">
      <template #footer>
        <div
          v-if="hasMore || failed || older.length > 0"
          class="flex items-center gap-3 border-t border-hairline px-4 py-2.5 text-sm text-text-3"
        >
          <span>{{ formatCount(page.events.length + older.length) }} shown</span>
          <ApButton
            size="compact"
            :disabled="loading || !hasMore"
            :disabled-reason="loading ? 'Loading…' : 'No older events'"
            @click="$emit('older')"
            >Load older</ApButton
          >
          <span v-if="failed" class="text-caution-text">Older events couldn't load.</span>
        </div>
      </template>
    </AuditTable>
  </ApPanel>
</template>
