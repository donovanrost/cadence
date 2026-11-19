<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ref } from "vue";
import type { ApiError } from "@/api";
import { ApButton, ApCallout, ApSheet } from "@/ui";
import { archiveDashboard } from "../settings/api.ts";
import { usedByPlaylists } from "../settings/present.ts";
import type { DirectoryRow } from "./api.ts";

/**
 * Archive with the director's Q10 rule: if playlists show this dashboard, say which ones and
 * ask again (present mode skips archived dashboards); archiving is audited.
 */
const props = defineProps<{ missionId: MissionId }>();
const emit = defineEmits<{ done: [] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const row = ref<DirectoryRow | null>(null);
const playlists = ref<readonly string[]>([]);
const error = ref<ApiError | null>(null);
const busy = ref(false);

function open(r: DirectoryRow) {
  row.value = r;
  playlists.value = [];
  error.value = null;
  sheet.value?.open();
}
async function submit() {
  if (!row.value || busy.value) return;
  busy.value = true;
  const key = { missionId: props.missionId, dashboardId: row.value.id };
  const result = await archiveDashboard(key, playlists.value.length > 0);
  busy.value = false;
  if (result.ok) {
    sheet.value?.close();
    emit("done");
    return;
  }
  const used = usedByPlaylists(result.error);
  if (used) playlists.value = used;
  else error.value = result.error;
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" :title="`Archive ${row?.name ?? 'dashboard'}?`">
    <div class="flex flex-col gap-3">
      <p class="m-0 text-base text-readout">
        Archived dashboards leave the directory; their links stop working.
      </p>
      <ApCallout v-if="playlists.length" tone="caution">
        Used in {{ playlists.length === 1 ? "a playlist" : `${playlists.length} playlists` }}:
        {{ playlists.join(", ") }}. Present mode will skip it until it's restored.
      </ApCallout>
      <ApCallout v-if="error" tone="crit">{{
        error.kind === "unauthenticated" ? "Signed out." : error.message
      }}</ApCallout>
    </div>
    <template #footer>
      <ApButton variant="secondary" class="mr-auto" @click="sheet?.close()">Keep it</ApButton>
      <ApButton variant="danger" :disabled="busy" disabled-reason="Archiving…" @click="submit">{{
        playlists.length ? "Archive anyway" : "Archive"
      }}</ApButton>
    </template>
  </ApSheet>
</template>
