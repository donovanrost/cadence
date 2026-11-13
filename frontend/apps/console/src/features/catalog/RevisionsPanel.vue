<script setup lang="ts">
import { ApPanel, ApTable, formatCount, formatShort, type ApColumn } from "@/ui";
import type { CatalogRevision } from "./api.ts";
import { ARTIFACT_LIVE } from "./artifact.ts";

/** Revisions of one catalog database, newest first. */
defineProps<{ revisions: readonly CatalogRevision[] }>();

const columns: readonly ApColumn[] = [
  { key: "number", label: "Revision", mono: true },
  { key: "label", label: "Label" },
  { key: "file", label: "Source file", mono: true },
  { key: "declarations", label: "Declarations", mono: true, align: "end" },
  { key: "used", label: "Used by", mono: true, align: "end" },
  { key: "imported", label: "Imported" },
];
</script>

<template>
  <ApPanel index="A1" title="Revisions" flush>
    <ApTable
      :columns="columns"
      :rows="revisions"
      :row-key="(r) => r.id"
      caption="Catalog revisions"
    >
      <template #cell-number="{ row }">rev {{ row.number }}</template>
      <template #cell-label="{ row }">{{ row.label ?? "—" }}</template>
      <template #cell-file="{ row }">
        <RouterLink
          v-if="ARTIFACT_LIVE"
          :to="{ name: 'setup.catalog.artifact', params: { artifactId: row.artifact.id } }"
          class="text-primary no-underline hover:underline"
          >{{ row.artifact.file_name }}</RouterLink
        >
        <span v-else class="text-text-2">{{ row.artifact.file_name }}</span>
        <a
          v-if="ARTIFACT_LIVE && row.artifact.download_url"
          :href="row.artifact.download_url"
          class="ml-2 text-xs text-primary no-underline hover:underline"
          >Download</a
        >
        <span class="block font-sans text-xs text-text-4">{{ row.artifact.format_label }}</span>
      </template>
      <template #cell-declarations="{ row }">{{ formatCount(row.declaration_count) }}</template>
      <template #cell-used="{ row }">
        <span v-if="row.spacecraft_count > 0">{{ formatCount(row.spacecraft_count) }} SC</span>
        <span v-else class="text-text-4">not used</span>
      </template>
      <template #cell-imported="{ row }">
        <time :datetime="row.imported_at" class="font-mono text-xs text-text-3">{{
          formatShort(new Date(row.imported_at))
        }}</time>
        <span v-if="row.actor" class="text-text-3"> · {{ row.actor.name }}</span>
      </template>
    </ApTable>
  </ApPanel>
</template>
