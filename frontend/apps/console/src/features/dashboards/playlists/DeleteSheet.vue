<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ref } from "vue";
import { ApButton, ApCallout, ApSheet } from "@/ui";
import { deletePlaylist, type PlaylistSummary } from "./api.ts";

/** Delete a playlist (Q10): a hard delete after this confirm; nothing else references it. */
const props = defineProps<{ missionId: MissionId }>();
const emit = defineEmits<{ deleted: [] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const target = ref<PlaylistSummary | null>(null);
const error = ref<string | null>(null);
const busy = ref(false);
function open(p: PlaylistSummary) {
  target.value = p;
  error.value = null;
  sheet.value?.open();
}
async function confirm() {
  if (!target.value || busy.value) return;
  busy.value = true;
  const r = await deletePlaylist(props.missionId, target.value.id);
  busy.value = false;
  if (!r.ok) {
    error.value = r.error.kind === "unauthenticated" ? "Signed out." : r.error.message;
    return;
  }
  sheet.value?.close();
  emit("deleted");
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" :title="`Delete ${target?.name ?? 'playlist'}?`">
    <p class="m-0 text-base text-readout">
      The playlist is deleted for everyone. Its dashboards aren't affected.
    </p>
    <ApCallout v-if="error" tone="crit">{{ error }}</ApCallout>
    <template #footer>
      <ApButton variant="secondary" class="mr-auto" @click="sheet?.close()">Keep it</ApButton>
      <ApButton variant="danger" :disabled="busy" disabled-reason="Deleting…" @click="confirm"
        >Delete playlist</ApButton
      >
    </template>
  </ApSheet>
</template>
