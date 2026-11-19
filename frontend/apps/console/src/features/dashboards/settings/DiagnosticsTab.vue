<script setup lang="ts">
import { useRemoteQuery } from "@/api";
import { ApEmptyState, ApPanel, ApRemote, formatShort } from "@/ui";
import { fetchDiagnostics, type SettingsKey } from "./api.ts";
import DiagnosticsRow from "./DiagnosticsRow.vue";
import { worstFirst } from "./present.ts";

/** Diagnostics (ux): one row per widget, worst first; no timings until the server records them (U20). */
const props = defineProps<{ settingsKey: SettingsKey }>();
const diag = useRemoteQuery(() => props.settingsKey, fetchDiagnostics);
</script>

<template>
  <ApRemote :state="diag.state.value" loading-label="Loading diagnostics…" @retry="diag.refetch">
    <template #default="{ value }">
      <ApPanel
        index="S6"
        title="Diagnostics"
        :meta="`v${value.version} · ${formatShort(new Date(value.loaded_at))}`"
        flush
      >
        <ApEmptyState v-if="value.widgets.length === 0" headline="No widgets to check" />
        <ul v-else class="m-0 list-none p-0">
          <DiagnosticsRow
            v-for="w in worstFirst(value.widgets)"
            :key="w.placement_id"
            :widget="w"
          />
        </ul>
      </ApPanel>
    </template>
  </ApRemote>
</template>
