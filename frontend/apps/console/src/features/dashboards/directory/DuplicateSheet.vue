<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ref } from "vue";
import { useRouter } from "vue-router";
import type { ApiError } from "@/api";
import { ApButton, ApCallout, ApField, ApSheet } from "@/ui";
import { duplicate, type DirectoryRow } from "./api.ts";

/** Duplicate: a new dashboard from the current version, opened in edit mode. */
const props = defineProps<{ missionId: MissionId }>();
const router = useRouter();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const row = ref<DirectoryRow | null>(null);
const name = ref("");
const error = ref<ApiError | null>(null);
const busy = ref(false);
function open(r: DirectoryRow) {
  row.value = r;
  name.value = `${r.name} (copy)`;
  error.value = null;
  sheet.value?.open();
}
async function submit() {
  if (!row.value || busy.value || !name.value.trim()) return;
  busy.value = true;
  const result = await duplicate(props.missionId, row.value.id, name.value.trim());
  busy.value = false;
  if (!result.ok) {
    error.value = result.error;
    return;
  }
  sheet.value?.close();
  void router.push({
    name: "ops.dashboard",
    params: { dashboardId: result.value.id },
    query: { edit: "1" },
  });
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" title="Duplicate dashboard" initial-focus="input">
    <div class="flex flex-col gap-3">
      <ApField v-model="name" label="Name" required />
      <ApCallout v-if="error" tone="crit">{{
        error.kind === "unauthenticated" ? "Signed out." : error.message
      }}</ApCallout>
    </div>
    <template #footer>
      <ApButton variant="secondary" class="mr-auto" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="primary"
        :disabled="busy || !name.trim()"
        disabled-reason="Give it a name."
        @click="submit"
        >Duplicate and edit</ApButton
      >
    </template>
  </ApSheet>
</template>
