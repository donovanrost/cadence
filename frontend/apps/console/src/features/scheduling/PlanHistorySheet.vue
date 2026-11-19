<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api";
import { ApRemote, ApSheet } from "@/ui";
import { fetchPlanHistory, historyLines } from "./plan-history.ts";
import PlanHistoryRow from "./PlanHistoryRow.vue";

/**
 * U73 (A10): the plan's history in a wide sheet, one list newest first, version and decision rows
 * in time order. Read only while open; it keeps K1's Gantt layout untouched.
 */
const props = defineProps<{ missionId: MissionId; planId: string; day: string }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const opened = ref(false);
const history = useRemoteQuery(
  computed(() => (opened.value ? { m: props.missionId, id: props.planId } : null)),
  (k, signal) => fetchPlanHistory(k.m, k.id, signal),
);
function open() {
  opened.value = true;
  history.refetch();
  sheet.value?.open();
}
defineExpose({ open });
</script>

<template>
  <ApSheet
    ref="sheet"
    :title="`Contact plan for ${day.slice(5)} · history`"
    width="wide"
    @closed="opened = false"
  >
    <ApRemote
      :state="history.state.value"
      loading-label="Loading history…"
      @retry="history.refetch"
    >
      <template #default="{ value }">
        <ul class="m-0 flex list-none flex-col p-0">
          <PlanHistoryRow
            v-for="row in historyLines(value, new Date(), day)"
            :key="row.key"
            :row="row"
          />
        </ul>
        <p v-if="value.truncated" class="m-0 pt-2 text-sm text-text-3">
          Older versions and decisions aren't shown.
        </p>
      </template>
    </ApRemote>
  </ApSheet>
</template>
