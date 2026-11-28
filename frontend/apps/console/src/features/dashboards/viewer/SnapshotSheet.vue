<script setup lang="ts">
import type { DashboardId } from "@/api/index.ts";
import type { MissionId } from "@/api/index.ts";
import { computed, nextTick, ref } from "vue";
import { RouterLink } from "vue-router";
import { fieldErrors } from "@/api";
import { ApButton, ApCallout, ApSegmented, ApSheet, formatShort, useNow } from "@/ui";
import { frozenBounds, type TimeSelection } from "../model/time-range.ts";
import { postSnapshot, type DataVisibility, type Snapshot } from "../settings/api.ts";

/**
 * ⋯ › Take snapshot (ux § Snapshots and shares, Q5): freezes the window on screen (a live range
 * becomes absolute now) at the current version. D16 POST /snapshots (api f4ef739b9).
 */
const props = defineProps<{
  missionId: MissionId;
  dashboardId: DashboardId;
  selection: TimeSelection;
  spacecraftId: string;
  version: number | null;
}>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const now = useNow();
const bounds = ref({ from: 0, to: 0 });
const data = ref<DataVisibility>("with_data");
const busy = ref(false);
const failure = ref<string | null>(null);
const taken = ref<Snapshot | null>(null);
const done = ref<HTMLElement | null>(null);
const options = [
  { value: "with_data", label: "With data" },
  { value: "definition_only", label: "Definition only" },
];
const setData = (v: string) => {
  if (v === "with_data" || v === "definition_only") data.value = v;
};
const windowText = computed(
  () => `${formatShort(new Date(bounds.value.from))}–${formatShort(new Date(bounds.value.to))}`,
);

function open() {
  bounds.value = frozenBounds(props.selection, now.value.getTime());
  data.value = "with_data";
  failure.value = null;
  taken.value = null;
  sheet.value?.open();
}
async function take() {
  if (busy.value) return;
  busy.value = true;
  failure.value = null;
  const r = await postSnapshot(props.missionId, props.dashboardId, {
    data_visibility: data.value,
    runtime: {
      from: new Date(bounds.value.from).toISOString(),
      to: new Date(bounds.value.to).toISOString(),
      spacecraft_id: props.spacecraftId || null,
    },
  });
  busy.value = false;
  if (r.ok) {
    taken.value = r.value;
    // Take snapshot is gone with the form; its result's link takes focus (a11y A5).
    await nextTick();
    done.value?.querySelector("a")?.focus();
    return;
  }
  // 422 names `runtime.from` / `runtime.to` / `runtime.spacecraft_id` / `data_visibility`.
  const fields = Object.values(fieldErrors(r.error));
  failure.value =
    fields[0] ?? (r.error.kind === "unauthenticated" ? "Signed out." : r.error.message);
}
defineExpose({ open });
</script>

<template>
  <!-- Opens on the Data choice, its first field (a11y A1). -->
  <ApSheet ref="sheet" title="Take snapshot" initial-focus="[role='radio'][tabindex='0']">
    <div v-if="taken" ref="done" class="flex flex-col gap-3">
      <ApCallout tone="nominal">Snapshot taken. It keeps this window and version.</ApCallout>
      <RouterLink
        :to="{ name: 'ops.dashboards.snapshot', params: { snapshotId: taken.id } }"
        class="text-readout underline-offset-2 hover:underline"
        >Open the snapshot</RouterLink
      >
    </div>
    <div v-else class="flex flex-col gap-4">
      <p class="m-0 font-mono text-md text-readout">
        {{ windowText }}<span v-if="version !== null"> · v{{ version }}</span>
      </p>
      <p class="m-0 text-sm text-text-3">
        The window you're looking at, frozen now. The snapshot doesn't change after this.
      </p>
      <ApSegmented
        :model-value="data"
        label="Data"
        :options="options"
        @update:model-value="setData"
      />
      <p v-if="data === 'definition_only'" class="m-0 text-sm text-text-3">
        Widgets show "Data isn't shared in this link."
      </p>
      <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
    </div>
    <template #footer>
      <ApButton variant="secondary" class="mr-auto" @click="sheet?.close()">{{
        taken ? "Close" : "Cancel"
      }}</ApButton>
      <ApButton
        v-if="!taken"
        variant="primary"
        :disabled="busy"
        disabled-reason="Taking the snapshot…"
        @click="take"
        >Take snapshot</ApButton
      >
    </template>
  </ApSheet>
</template>
