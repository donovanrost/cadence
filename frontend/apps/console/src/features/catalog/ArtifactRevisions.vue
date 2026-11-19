<script setup lang="ts">
import { ApButton, ApEmptyState, ApPanel, ApTable, formatShort, plural, type ApColumn } from "@/ui";
import type { ArtifactPage } from "./artifact.ts";
import type { RunMatch } from "./matchedRevision.ts";
import { noOwnRevision, openMatchLabel } from "./matchedWords.ts";

/**
 * F1 · the catalog revisions this file made (L18). `match`: its content matched a revision this
 * database already has, so it made none of its own (#119 U99), and the usual empty state is false.
 */
defineProps<{ revisions: ArtifactPage["revisions"]; match?: RunMatch | undefined }>();
const columns: readonly ApColumn[] = [
  { key: "number", label: "Revision", mono: true },
  { key: "label", label: "Label" },
  { key: "imported", label: "Imported", mono: true },
];
</script>

<template>
  <ApPanel
    index="F1"
    title="Revisions from this file"
    :meta="plural(revisions.length, 'revision')"
    flush
  >
    <ApEmptyState v-if="revisions.length === 0 && match" state="off" v-bind="noOwnRevision(match)">
      <ApButton
        v-if="match.model_revision_id"
        size="compact"
        :to="{ name: 'setup.catalog.model', params: { revisionId: match.model_revision_id } }"
        >{{ openMatchLabel(match) }}</ApButton
      >
    </ApEmptyState>
    <ApEmptyState
      v-else-if="revisions.length === 0"
      state="off"
      headline="No revisions yet"
      sentence="An import of this file becomes a revision once it's valid."
    />
    <ApTable
      v-else
      :columns="columns"
      :rows="revisions"
      :row-key="(r) => r.id"
      caption="Revisions from this file"
    >
      <template #cell-number="{ row }">rev {{ row.number }}</template>
      <template #cell-label="{ row }">{{ row.label ?? "—" }}</template>
      <template #cell-imported="{ row }">{{ formatShort(new Date(row.imported_at)) }}</template>
    </ApTable>
  </ApPanel>
</template>
