<script setup lang="ts">
import type { DashboardSettings, SettingsKey } from "./api.ts";
import SharesPanel from "./SharesPanel.vue";
import SnapshotsPanel from "./SnapshotsPanel.vue";

/** Sharing (ux § Snapshots and shares): share links, then the read-only snapshots. */
defineProps<{ settingsKey: SettingsKey; settings: DashboardSettings }>();
defineEmits<{ changed: [] }>();
</script>

<template>
  <SharesPanel
    :settings-key="settingsKey"
    :shares="settings.shares.rows"
    @changed="$emit('changed')"
  />
  <SnapshotsPanel :dashboard-id="settingsKey.dashboardId" :snapshots="settings.snapshots.rows" />
</template>
