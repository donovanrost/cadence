<script setup lang="ts">
import { ApPanel, ApTable, formatAbsolute, type ApColumn } from "@/ui";
import type { ProfileDetail } from "./detail.ts";

/** History (v1): profile versions. Field diffs and authors arrive with change-set revisions. */
defineProps<{ detail: ProfileDetail }>();
const columns: readonly ApColumn[] = [
  { key: "version", label: "Version", mono: true },
  { key: "created", label: "Created", mono: true },
  { key: "by", label: "By" },
];
</script>

<template>
  <ApPanel index="P5" title="History" :meta="`${detail.versions.length} versions`" flush>
    <ApTable
      :columns="columns"
      :rows="detail.versions"
      :row-key="(v) => String(v.version)"
      caption="Profile versions"
    >
      <template #cell-version="{ row }">
        v{{ row.version
        }}<span v-if="row.version === detail.profile.version" class="font-sans text-xs text-text-3">
          · latest</span
        >
      </template>
      <template #cell-created="{ row }">{{ formatAbsolute(new Date(row.created_at)) }}</template>
      <template #cell-by="{ row }">
        <span :class="row.actor ? 'text-readout' : 'text-text-3'">{{
          row.actor?.name ?? "Not recorded"
        }}</span>
      </template>
    </ApTable>
  </ApPanel>
</template>
