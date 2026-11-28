<script setup lang="ts">
import type { DashboardId } from "@/api/index.ts";
import type { MissionId } from "@/api/index.ts";
import { computed, nextTick, ref } from "vue";
import {
  ApButton,
  ApCallout,
  ApField,
  ApNumberField,
  ApSheet,
  ApTextarea,
  refocusFirst,
} from "@/ui";
import {
  DWELL,
  changedPlaylist,
  createPlaylist,
  fetchPlaylist,
  refusedDashboards,
  updatePlaylist,
  type Playlist,
  type PlaylistSummary,
} from "./api.ts";
import PlaylistConflict from "./PlaylistConflict.vue";
import PlaylistOrder from "./PlaylistOrder.vue";

/** New / edit playlist (ux: a wide sheet): name, dwell, wallboard mode, ordered dashboards. */
const props = defineProps<{ missionId: MissionId }>();
const emit = defineEmits<{ saved: [] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const id = ref<string | null>(null);
const name = ref("");
const description = ref("");
const dwell = ref("30");
const wallboard = ref(false);
const dashboards = ref<readonly { id: DashboardId; name: string; archived: boolean }[]>([]);
/** The row's `updated_at` as read: a stale one is 409 version_conflict (§D24). */
const expectedUpdatedAt = ref<string | null>(null);
const conflict = ref<Playlist | null>(null);
const error = ref<string | null>(null);
const busy = ref(false);
const dwellSeconds = computed(() => Number.parseInt(dwell.value, 10));
const archived = computed(() => dashboards.value.filter((d) => d.archived).length);
const blocked = computed(() => {
  if (name.value.trim() === "" || dashboards.value.length === 0)
    return "Name it and add a dashboard.";
  if (!(dwellSeconds.value >= DWELL.min && dwellSeconds.value <= DWELL.max))
    return `Pick a dwell of ${DWELL.min} to ${DWELL.max} s.`;
  // The server refuses archived dashboards in a saved playlist (§D24).
  if (archived.value) return "Remove the archived dashboards first.";
  return null;
});

function fill(from: Playlist | PlaylistSummary) {
  name.value = from.name;
  description.value = from.description ?? "";
  dwell.value = String(from.dwell_seconds);
  wallboard.value = from.wallboard_mode;
  expectedUpdatedAt.value = from.updated_at;
}
async function open(existing: PlaylistSummary | null) {
  id.value = existing?.id ?? null;
  if (existing) fill(existing);
  else {
    name.value = description.value = "";
    dwell.value = "30";
    wallboard.value = false;
    expectedUpdatedAt.value = null;
  }
  dashboards.value = [];
  error.value = null;
  conflict.value = null;
  sheet.value?.open();
  if (existing) {
    const r = await fetchPlaylist(props.missionId, existing.id);
    if (r.ok) {
      fill(r.value);
      dashboards.value = r.value.dashboards;
    } else error.value = r.error.kind === "unauthenticated" ? "Signed out." : r.error.message;
  }
}
async function save() {
  if (blocked.value || busy.value) return;
  busy.value = true;
  error.value = null;
  const body = {
    name: name.value.trim(),
    description: description.value.trim(),
    dwell_seconds: dwellSeconds.value,
    wallboard_mode: wallboard.value,
    dashboard_ids: dashboards.value.map((d) => d.id),
  };
  const r = id.value
    ? await updatePlaylist(props.missionId, id.value, body, expectedUpdatedAt.value)
    : await createPlaylist(props.missionId, body);
  busy.value = false;
  if (r.ok) {
    sheet.value?.close();
    return void emit("saved");
  }
  conflict.value = changedPlaylist(r.error);
  if (conflict.value) return;
  const refused = refusedDashboards(r.error);
  if (refused.length) {
    // Archived (or gone) since they were added: flag them so they can be removed.
    dashboards.value = dashboards.value.map((d) =>
      refused.includes(d.id) ? { ...d, archived: true } : d,
    );
    return void (error.value = "Some dashboards are archived or no longer in this mission.");
  }
  error.value = r.error.kind === "unauthenticated" ? "Signed out." : r.error.message;
}
/**
 * Someone saved meanwhile: take their playlist, or keep mine over it. Either button leaves with
 * the conflict, so focus goes to Name, the top of the form now holding the playlist (A5).
 */
const form = ref<HTMLElement | null>(null);
async function refocusName() {
  await nextTick();
  refocusFirst(form.value?.querySelector<HTMLElement>("input"));
}
function useTheirs(current: Playlist) {
  fill(current);
  dashboards.value = current.dashboards;
  conflict.value = null;
  void refocusName();
}
function keepMine(current: Playlist) {
  expectedUpdatedAt.value = current.updated_at;
  conflict.value = null;
  void refocusName();
  void save();
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
    <div ref="form" class="flex flex-col gap-3">
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
      <PlaylistConflict v-if="conflict" :current="conflict" @theirs="useTheirs" @mine="keepMine" />
      <ApCallout v-if="error" tone="crit">{{ error }}</ApCallout>
    </div>
    <template #footer>
      <ApButton variant="secondary" class="mr-auto" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="primary"
        :disabled="blocked !== null || busy"
        :disabled-reason="blocked ?? 'Saving…'"
        @click="save"
        >{{ id ? "Save playlist" : "Create playlist" }}</ApButton
      >
    </template>
  </ApSheet>
</template>
