<script setup lang="ts">
import { computed } from "vue";
import { describeApiError, usePagedQuery, type MissionId } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import {
  ApButton,
  ApEmptyState,
  ApPanel,
  ApRemote,
  ApTable,
  formatCount,
  plural,
  type ApColumn,
} from "@/ui";
import {
  craftName,
  fetchRevisionSpacecraftPage,
  usesText,
  versionText,
  type RevisionSpacecraftKey,
} from "../revisionSpacecraft.ts";

/**
 * #678: the spacecraft that use this catalog revision (their latest saved configuration names it,
 * or their active generation runs it), a page at a time, counted by the server. Read again when
 * the catalog, a configuration or an activation changes.
 */
const props = defineProps<{ missionId: MissionId; catalogRevisionId: string }>();
const key = computed<RevisionSpacecraftKey>(() => ({
  missionId: props.missionId,
  catalogRevisionId: props.catalogRevisionId,
}));
const pages = usePagedQuery(key, fetchRevisionSpacecraftPage, (row) => row.id);
useMissionInvalidation(
  computed(() => props.missionId),
  ["catalog", "configuration", "activations"],
  pages.refetch,
);
const total = computed(() =>
  pages.state.value.status === "ready" ? pages.state.value.value.meta.total : null,
);
const columns: readonly ApColumn[] = [
  { key: "name", label: "Spacecraft" },
  { key: "uses", label: "Uses it in" },
  { key: "version", label: "Configuration", mono: true },
];
</script>

<template>
  <ApPanel
    index="F2"
    title="Spacecraft using it"
    :meta="total === null ? undefined : plural(total, 'spacecraft', 'spacecraft')"
    flush
  >
    <ApRemote
      :state="pages.state.value"
      loading-label="Loading the spacecraft…"
      @retry="pages.refetch"
    >
      <template #default="{ value: page }">
        <p
          v-if="pages.refreshError.value"
          role="status"
          class="m-0 px-4 py-2 text-sm text-caution-text"
        >
          Couldn't refresh the list: {{ describeApiError(pages.refreshError.value) }}. Showing what
          was read before.
        </p>
        <ApEmptyState
          v-if="page.items.length === 0"
          state="off"
          headline="No spacecraft use this revision"
          sentence="No spacecraft's saved configuration names it, and none runs it."
        />
        <ApTable
          v-else
          :columns="columns"
          :rows="page.items"
          :row-key="(r) => r.id"
          caption="Spacecraft using this catalog revision"
        >
          <template #cell-name="{ row }">
            <RouterLink
              :to="{ name: 'setup.spacecraft.one', params: { spacecraftId: row.id } }"
              class="font-semibold text-readout no-underline hover:underline max-md:hit-44"
              >{{ craftName(row) }}</RouterLink
            >
            <span class="font-mono text-xs text-text-3"> SCID {{ row.scid ?? "not set" }}</span>
          </template>
          <template #cell-uses="{ row }">{{ usesText(row) }}</template>
          <template #cell-version="{ row }">{{ versionText(row) }}</template>
          <template #footer>
            <div
              class="flex flex-wrap items-center gap-3 border-t border-hairline px-4 py-2.5 text-sm text-text-3"
            >
              <span
                >{{ formatCount(page.items.length) }} of
                {{ formatCount(page.meta.total) }} shown</span
              >
              <ApButton
                size="compact"
                :disabled="pages.moreBusy.value || page.next === null"
                :disabled-reason="pages.moreBusy.value ? 'Loading…' : 'Every spacecraft is shown'"
                @click="pages.more"
                >Load more</ApButton
              >
              <!-- It answers the person's own click: an alert, always mounted (a11y B6). -->
              <span role="alert" class="text-caution-text">{{
                pages.moreError.value
                  ? `Couldn't load more: ${describeApiError(pages.moreError.value)}`
                  : ""
              }}</span>
            </div>
          </template>
        </ApTable>
      </template>
    </ApRemote>
  </ApPanel>
</template>
