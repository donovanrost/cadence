<script setup lang="ts">
import { ApPanel, ApTable, formatAbsolute, formatCount, type ApColumn } from "@/ui";
import type { ProfileDetail } from "./detail.ts";
import ProfileRevisions from "./ProfileRevisions.vue";

/**
 * Profile.md History: versions with how many spacecraft are on each (drift is visible), then the
 * revisions that touched the profile with their field diffs.
 */
defineProps<{ detail: ProfileDetail }>();
const columns: readonly ApColumn[] = [
  { key: "version", label: "Version", mono: true },
  { key: "on", label: "Spacecraft on it", align: "end", mono: true },
  { key: "created", label: "Created", mono: true },
  { key: "by", label: "By" },
];
</script>

<template>
  <ApPanel index="P5" title="Versions" :meta="`${detail.versions.length} versions`" flush>
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
      <template #cell-on="{ row }">{{
        row.spacecraft_count === undefined ? "—" : formatCount(row.spacecraft_count)
      }}</template>
      <template #cell-created="{ row }">{{ formatAbsolute(new Date(row.created_at)) }}</template>
      <template #cell-by="{ row }">
        <span :class="row.actor ? 'text-readout' : 'text-text-3'">{{
          row.actor?.name ?? "Not recorded"
        }}</span>
      </template>
    </ApTable>
  </ApPanel>
  <ProfileRevisions :profile-id="detail.profile.id" />
</template>
