<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import {
  ApEmptyState,
  ApPageHeader,
  ApPanel,
  ApRemote,
  ApStatusMark,
  ApTable,
  formatDuration,
  formatShort,
  plural,
  type ApColumn,
  type OpState,
} from "@/ui";
import { fetchSources, type DataSource } from "./api.ts";

/** Setup › Data sources (rail 07): freshness and health as the server judges them (U9). */
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const { state, refetch } = useRemoteQuery(missionId, fetchSources);
useMissionInvalidation(missionId, ["data_sources"], refetch);
const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
const columns: readonly ApColumn[] = [
  { key: "name", label: "Source" },
  { key: "kind", label: "Kind" },
  { key: "fresh", label: "Freshness" },
  { key: "health", label: "Health" },
  { key: "creds", label: "Credentials" },
];
function freshness(s: DataSource): { state: OpState; text: string } {
  if (s.last_received_at === null) return { state: "off", text: "Nothing received yet" };
  const at = formatShort(new Date(s.last_received_at));
  if (s.stale === true)
    return {
      state: "stale",
      text: `Late · last ${at}${s.expected_interval_s ? `, expected every ${formatDuration(s.expected_interval_s)}` : ""}`,
    };
  if (s.stale === false) return { state: "nominal", text: `Fresh · last ${at}` };
  return { state: "neutral", text: `Last ${at}` };
}
const healthState = (s: DataSource): OpState =>
  s.health === null || s.health.status === "unknown"
    ? "off"
    : s.health.status === "healthy"
      ? "nominal"
      : "caution";
const healthText = (s: DataSource) =>
  s.health === null || s.health.status === "unknown"
    ? "Not reported"
    : s.health.status === "healthy"
      ? "Healthy"
      : "Degraded";
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader
      :label="`${scope.mission.name} · data sources`"
      :title="state.status === 'ready' ? plural(state.value.length, 'source') : 'Data sources'"
      size="reading"
    />
    <ApPanel index="D1" title="Sources" flush>
      <ApEmptyState
        v-if="notProvided"
        state="off"
        headline="Data sources not available in the console yet"
        sentence="This server doesn't serve data sources to the console yet."
      />
      <ApRemote v-else :state="state" loading-label="Loading data sources…" @retry="refetch">
        <template #default="{ value }">
          <ApEmptyState
            v-if="value.length === 0"
            state="off"
            headline="No data sources"
            sentence="Telemetry is stored in the mission's data sources."
          />
          <ApTable
            v-else
            :columns="columns"
            :rows="value"
            :row-key="(s) => s.id"
            caption="Data sources"
          >
            <template #cell-name="{ row }"
              ><span class="font-semibold text-readout">{{ row.display_name }}</span></template
            >
            <template #cell-kind="{ row }"
              ><span class="text-text-2">{{ row.kind.replaceAll("_", " ") }}</span
              ><span class="text-text-4"> · {{ row.owner }}</span></template
            >
            <template #cell-fresh="{ row }"
              ><span class="inline-flex items-center gap-2"
                ><ApStatusMark :state="freshness(row).state" />{{ freshness(row).text }}</span
              ></template
            >
            <template #cell-health="{ row }"
              ><span class="inline-flex items-center gap-2"
                ><ApStatusMark :state="healthState(row)" />{{ healthText(row) }}</span
              ></template
            >
            <template #cell-creds="{ row }">
              <span
                :class="
                  row.credentials?.status === 'expired'
                    ? 'text-crit-text'
                    : row.credentials?.status === 'expiring'
                      ? 'text-caution-text'
                      : 'text-text-3'
                "
                >{{ row.credentials?.status ?? "—" }}</span
              >
            </template>
          </ApTable>
        </template>
      </ApRemote>
    </ApPanel>
  </div>
</template>
