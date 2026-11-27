<script setup lang="ts">
import { computed } from "vue";
import { describeApiError, usePagedQuery, useRemoteQuery, type MissionId } from "@/api";
import type { SpacecraftId } from "@/api";
import { useMissionInvalidation } from "@/live";
import {
  ApEmptyState,
  ApKeyValue,
  ApPanel,
  ApRemote,
  ApTable,
  ApTag,
  formatAbsolute,
  useNow,
  type ApColumn,
} from "@/ui";
import OrbitPagedFooter from "./OrbitPagedFooter.vue";
import {
  fetchCurrentElementSet,
  fetchElementSetPage,
  type ElementSet,
  type OrbitKey,
} from "./api.ts";
import { currentFacts, formatWords, sourceLine } from "./words.ts";

/**
 * D7 Orbit (#895): the spacecraft's current element set and its history, newest epoch first.
 * Storing a set starts a recompute, whose end is the `predicted_passes` invalidation.
 */
const props = defineProps<{ missionId: MissionId; spacecraftId: SpacecraftId }>();
const now = useNow();
const key = computed((): OrbitKey => ({
  missionId: props.missionId,
  spacecraftId: props.spacecraftId,
}));
const current = useRemoteQuery(key, fetchCurrentElementSet);
const set = computed(() =>
  current.state.value.status === "ready" ? current.state.value.value : null,
);
// The history is read once there is a current set: none means none stored.
const history = usePagedQuery(
  computed(() => (set.value ? key.value : null)),
  fetchElementSetPage,
  (s) => s.id,
);
useMissionInvalidation(
  computed(() => props.missionId),
  ["predicted_passes"],
  () => {
    current.refetch();
    history.refetch();
  },
);
const columns: readonly ApColumn[] = [
  { key: "epoch", label: "Epoch", mono: true },
  { key: "format", label: "Format" },
  { key: "source", label: "Source" },
  { key: "norad", label: "NORAD id", mono: true },
  { key: "received", label: "Received", mono: true },
];
const received = (s: ElementSet) => formatAbsolute(new Date(s.received_at));
</script>

<template>
  <ApPanel index="D7" title="Orbit" flush>
    <ApRemote
      :state="current.state.value"
      loading-label="Loading the orbit…"
      @retry="current.refetch"
    >
      <template #default="{ value }">
        <ApEmptyState
          v-if="value === null"
          state="off"
          headline="No orbit stored"
          sentence="Cadence predicts this spacecraft's passes once an element set (TLE or OMM) is stored for it."
        />
        <div v-else class="flex flex-col">
          <div class="px-4 py-3">
            <ApKeyValue :items="currentFacts(value, now)" :columns="2" />
          </div>
          <h3 class="ap-label m-0 border-t border-hairline px-4 pt-3 pb-1.5">History</h3>
          <ApRemote
            :state="history.state.value"
            loading-label="Loading the history…"
            @retry="history.refetch"
          >
            <template #default="{ value: page }">
              <p
                v-if="history.refreshError.value"
                role="status"
                class="m-0 px-4 pb-2 text-sm text-caution-text"
              >
                Couldn't refresh the history: {{ describeApiError(history.refreshError.value) }}.
                Showing what was read before.
              </p>
              <ApTable
                :columns="columns"
                :rows="page.items"
                :row-key="(s) => s.id"
                caption="Element-set history, newest epoch first"
              >
                <template #cell-epoch="{ row }">
                  {{ formatAbsolute(new Date(row.epoch)) }}
                  <ApTag v-if="row.id === value.id" state="nominal" label="Current" />
                </template>
                <template #cell-format="{ row }">{{ formatWords[row.format] }}</template>
                <template #cell-source="{ row }">{{ sourceLine(row) }}</template>
                <template #cell-norad="{ row }">{{ row.norad_id ?? "Not in the set" }}</template>
                <template #cell-received="{ row }">{{ received(row) }}</template>
                <template #footer>
                  <OrbitPagedFooter
                    :shown="page.items.length"
                    :has-more="page.next !== null"
                    :loading="history.moreBusy.value"
                    :error="history.moreError.value"
                    no-more="No older element sets"
                    @more="history.more"
                  />
                </template>
              </ApTable>
            </template>
          </ApRemote>
        </div>
      </template>
    </ApRemote>
  </ApPanel>
</template>
