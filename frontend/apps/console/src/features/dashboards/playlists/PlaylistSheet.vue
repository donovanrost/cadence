<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton, ApCallout, ApField, ApNumberField, ApSheet, ApTextarea } from "@/ui";
import {
  DWELL,
  createPlaylist,
  fetchPlaylist,
  updatePlaylist,
  type PlaylistSummary,
} from "./api.ts";
import PlaylistOrder from "./PlaylistOrder.vue";

/** New / edit playlist (ux: a wide sheet): name, dwell, wallboard mode, ordered dashboards. */
const props = defineProps<{ missionId: string }>();
const emit = defineEmits<{ saved: [] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const id = ref<string | null>(null);
const name = ref("");
const description = ref("");
const dwell = ref("30");
const wallboard = ref(false);
const dashboards = ref<readonly { id: string; name: string; archived: boolean }[]>([]);
const error = ref<string | null>(null);
const busy = ref(false);
const dwellSeconds = computed(() => Number.parseInt(dwell.value, 10));
const valid = computed(
  () =>
    name.value.trim() !== "" &&
    dashboards.value.length > 0 &&
    dwellSeconds.value >= DWELL.min &&
    dwellSeconds.value <= DWELL.max,
);

async function open(existing: PlaylistSummary | null) {
  id.value = existing?.id ?? null;
  name.value = existing?.name ?? "";
  description.value = existing?.description ?? "";
  dwell.value = String(existing?.dwell_seconds ?? 30);
  wallboard.value = existing?.wallboard_mode ?? false;
  dashboards.value = [];
  error.value = null;
  sheet.value?.open();
  if (existing) {
    const r = await fetchPlaylist(props.missionId, existing.id);
    if (r.ok) dashboards.value = r.value.dashboards;
    else error.value = r.error.kind === "unauthenticated" ? "Signed out." : r.error.message;
  }
}
async function save() {
  if (!valid.value || busy.value) return;
  busy.value = true;
  const body = {
    name: name.value.trim(),
    description: description.value.trim(),
    dwell_seconds: dwellSeconds.value,
    wallboard_mode: wallboard.value,
    dashboard_ids: dashboards.value.map((d) => d.id),
  };
  const r = id.value
    ? await updatePlaylist(props.missionId, id.value, body)
    : await createPlaylist(props.missionId, body);
  busy.value = false;
  if (!r.ok) {
    error.value = r.error.kind === "unauthenticated" ? "Signed out." : r.error.message;
    return;
  }
  sheet.value?.close();
  emit("saved");
}
defineExpose({ open });
</script>

<template>
  <ApSheet
    ref="sheet"
    :title="id ? 'Edit playlist' : 'New playlist'"
    width="wide"
    initial-focus="input"
  >
    <div class="flex flex-col gap-3">
      <ApField v-model="name" label="Name" required />
      <ApTextarea v-model="description" label="Description (optional)" :rows="2" :maxlength="500" />
      <div class="flex items-end gap-4">
        <ApNumberField
          v-model="dwell"
          label="Dwell"
          unit="s"
          :min="DWELL.min"
          :max="DWELL.max"
          integer
          :hint="`${DWELL.min}–${DWELL.max} seconds per dashboard`"
        />
        <label class="flex items-center gap-2 pb-2 text-md text-readout">
          <input
            v-model="wallboard"
            type="checkbox"
            class="accent-[var(--color-readout)] [color-scheme:dark]"
          />
          Wallboard mode
        </label>
      </div>
      <PlaylistOrder v-model="dashboards" :mission-id="missionId" />
      <ApCallout v-if="error" tone="crit">{{ error }}</ApCallout>
    </div>
    <template #footer>
      <ApButton variant="secondary" class="mr-auto" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="primary"
        :disabled="!valid || busy"
        disabled-reason="Name it, add a dashboard and pick a dwell of 10 to 3600 s."
        @click="save"
        >{{ id ? "Save playlist" : "Create playlist" }}</ApButton
      >
    </template>
  </ApSheet>
</template>
