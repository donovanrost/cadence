<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { ApEmptyState, ApPanel, ApRemote, ApTable, ApTag, type ApColumn } from "@/ui";
import { fetchScopedApps } from "./api.ts";
import { statusTag } from "./host.ts";
import { setupSurfaces } from "./surfaces.ts";

/** L19 · the apps that work per spacecraft (telemetry decom, spacecraft), for this spacecraft. */
const props = defineProps<{ missionId: string; spacecraftId: string }>();
const apps = useRemoteQuery(
  () => ({ missionId: props.missionId, spacecraftId: props.spacecraftId }),
  fetchScopedApps,
);
const notProvided = computed(
  () => apps.state.value.status === "failed" && apps.state.value.error.kind === "not_found",
);
const columns: readonly ApColumn[] = [
  { key: "name", label: "App" },
  { key: "status", label: "Status" },
  { key: "version", label: "Version", mono: true },
];
</script>

<template>
  <ApPanel index="S9" title="Apps" flush>
    <ApEmptyState
      v-if="notProvided"
      state="off"
      headline="Spacecraft apps aren't available in the console yet"
    />
    <ApRemote v-else :state="apps.state.value" loading-label="Loading apps…" @retry="apps.refetch">
      <template #default="{ value }">
        <ApEmptyState
          v-if="value.apps.length === 0"
          state="off"
          headline="No apps work per spacecraft"
        />
        <ApTable
          v-else
          :columns="columns"
          :rows="value.apps"
          :row-key="(a) => a.key"
          caption="Apps"
        >
          <template #cell-name="{ row }">
            <RouterLink
              v-if="row.installed && setupSurfaces(row.surfaces).length > 0"
              :to="{ name: 'setup.spacecraft.app', params: { spacecraftId, appKey: row.key } }"
              class="font-semibold text-primary no-underline hover:underline max-md:hit-44"
              >{{ row.name }}</RouterLink
            >
            <span v-else class="font-semibold text-readout">{{ row.name }}</span>
          </template>
          <template #cell-status="{ row }"
            ><ApTag
              v-if="row.status"
              :state="statusTag[row.status.state].state"
              :label="statusTag[row.status.state].label"
            /><span v-else class="text-text-3">{{
              row.installed ? "Installed" : "Not set up"
            }}</span></template
          >
          <template #cell-version="{ row }">{{ row.version ? `v${row.version}` : "—" }}</template>
        </ApTable>
      </template>
    </ApRemote>
  </ApPanel>
</template>
