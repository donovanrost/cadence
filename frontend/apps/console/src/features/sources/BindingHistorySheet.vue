<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ref } from "vue";
import { useRemoteQuery } from "@/api";
import { ApEmptyState, ApRemote, ApSheet, ApTable, formatShort, type ApColumn } from "@/ui";
import { fetchBindingEvents, type BindingEvent } from "./bindings.ts";
import { eventLine, historyWho } from "./platform.ts";

/** U53: a binding's history (newest first, 50), with the platform switch's audit line. */
const props = defineProps<{ missionId: MissionId }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
type Opened = Readonly<{ id: string; logical_source: string; shared?: boolean | undefined }>;
const binding = ref<Opened | null>(null);
const key = ref<{ missionId: MissionId; bindingId: string } | null>(null);
const events = useRemoteQuery(key, fetchBindingEvents);
const columns: readonly ApColumn[] = [
  { key: "at", label: "When", mono: true },
  { key: "who", label: "Who" },
  { key: "what", label: "What" },
];
const eventKey = (e: BindingEvent) =>
  `${e.at}|${typeof e.kind === "string" ? e.kind : e.kind.unrecognized}`;
function open(b: Opened) {
  binding.value = b;
  key.value = { missionId: props.missionId, bindingId: b.id };
  sheet.value?.open();
}
defineExpose({ open });
</script>

<template>
  <ApSheet
    ref="sheet"
    :title="`${binding?.logical_source ?? 'Binding'} history`"
    width="wide"
    @closed="key = null"
  >
    <ApRemote :state="events.state.value" loading-label="Loading history…" @retry="events.refetch">
      <template #default="{ value }">
        <ApEmptyState
          v-if="value.length === 0"
          state="off"
          headline="No history yet"
          sentence="Nothing has changed this binding."
        />
        <ApTable v-else :columns="columns" :rows="value" :row-key="eventKey" caption="History">
          <template #cell-at="{ row }">{{ formatShort(new Date(row.at)) }}</template>
          <template #cell-who="{ row }">{{ historyWho(row, binding?.shared === true) }}</template>
          <template #cell-what="{ row }">{{
            eventLine(row, binding?.logical_source ?? "")
          }}</template>
        </ApTable>
      </template>
    </ApRemote>
  </ApSheet>
</template>
