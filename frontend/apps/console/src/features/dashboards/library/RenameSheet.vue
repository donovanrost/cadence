<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ref } from "vue";
import { describeApiError, fieldErrors, isError } from "@/api";
import { ApButton, ApCallout, ApField, ApSheet, ApTextarea } from "@/ui";
import { renameItem } from "./api.ts";

/** Rename a library widget (D22 PATCH): name and description, against the version on screen. */
const props = defineProps<{ missionId: MissionId }>();
const emit = defineEmits<{ done: [] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const target = ref<{ id: string; version: number; updatedAt: string | null } | null>(null);
const name = ref("");
const description = ref("");
const error = ref<string | null>(null);
const busy = ref(false);

function open(item: {
  id: string;
  name: string;
  description: string | null;
  latest_version: number;
  updated_at: string | null;
}) {
  target.value = { id: item.id, version: item.latest_version, updatedAt: item.updated_at };
  name.value = item.name;
  description.value = item.description ?? "";
  error.value = null;
  sheet.value?.open();
}
async function save() {
  const t = target.value;
  if (!t || busy.value || !name.value.trim()) return;
  busy.value = true;
  const r = await renameItem(props.missionId, t.id, {
    name: name.value.trim(),
    description: description.value.trim(),
    expected_version: t.version,
    // A rename adds no version, so the row's updated_at is what catches a stale tab (qa 13:36Z).
    expected_updated_at: t.updatedAt,
  });
  busy.value = false;
  if (r.ok) {
    sheet.value?.close();
    emit("done");
  } else
    error.value = isError(r.error, "library_item_changed")
      ? "Someone changed this widget meanwhile. Close and open it again to rename the current one."
      : r.error.kind === "forbidden"
        ? "Dashboard editors manage the library."
        : r.error.kind === "not_found"
          ? "This widget was deleted meanwhile."
          : // 422 details.request (bad name) or details.expected_version: the server's sentence.
            (fieldErrors(r.error).request ??
            fieldErrors(r.error).expected_version ??
            describeApiError(r.error));
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" title="Rename library widget" initial-focus="input">
    <ApField v-model="name" label="Name" required />
    <ApTextarea v-model="description" label="Description" :rows="3" />
    <ApCallout v-if="error" tone="caution" role="alert">{{ error }}</ApCallout>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <!-- An empty name disables Rename and says why (ux a11y A6: one pattern per form). -->
      <ApButton
        variant="primary"
        :disabled="busy || !name.trim()"
        :disabled-reason="busy ? 'Saving…' : 'Give it a name.'"
        @click="save"
        >Rename</ApButton
      >
    </template>
  </ApSheet>
</template>
