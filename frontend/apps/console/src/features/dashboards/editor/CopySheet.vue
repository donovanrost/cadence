<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ref } from "vue";
import { useRouter } from "vue-router";
import { ApButton, ApCallout, ApField, ApSheet } from "@/ui";
import { copy } from "./api.ts";
import type { Draft } from "./draft.ts";

/**
 * ⋯ › Save as copy (D11): a new dashboard from the current version plus any unsaved edits, opened
 * in edit mode. This dashboard stays as it was saved; the edits move to the copy.
 */
const props = defineProps<{ missionId: MissionId; dashboardId: string; name: string }>();
const emit = defineEmits<{ copied: [] }>();
const router = useRouter();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const title = ref("");
const draft = ref<Draft | null>(null);
const error = ref<string | null>(null);
const busy = ref(false);
function open(from: Draft) {
  draft.value = from;
  title.value = `${props.name} (copy)`;
  error.value = null;
  sheet.value?.open();
}
async function submit() {
  if (!draft.value || busy.value || !title.value.trim()) return;
  busy.value = true;
  const result = await copy(props.missionId, props.dashboardId, draft.value, title.value.trim());
  busy.value = false;
  if (!result.ok) {
    error.value = result.error.kind === "unauthenticated" ? "Signed out." : result.error.message;
    return;
  }
  sheet.value?.close();
  emit("copied");
  void router.push({
    name: "ops.dashboard",
    params: { dashboardId: result.value.id },
    query: { edit: "1" },
  });
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" title="Save as copy" initial-focus="input">
    <div class="flex flex-col gap-3">
      <ApField v-model="title" label="Name" required />
      <p v-if="draft?.commands.length" class="m-0 text-sm text-text-3">
        The copy includes your {{ draft.commands.length }} unsaved
        {{ draft.commands.length === 1 ? "change" : "changes" }}. This dashboard stays as it was
        saved.
      </p>
      <ApCallout v-if="error" tone="crit">{{ error }}</ApCallout>
    </div>
    <template #footer>
      <ApButton variant="secondary" class="mr-auto" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="primary"
        :disabled="busy || !title.trim()"
        disabled-reason="Give it a name."
        @click="submit"
        >Save copy and edit</ApButton
      >
    </template>
  </ApSheet>
</template>
