<script setup lang="ts">
import type { DashboardId } from "@/api/index.ts";
import type { MissionId } from "@/api/index.ts";
import { nextTick, ref } from "vue";
import { useRouter } from "vue-router";
import { ApButton, ApCallout, ApField, ApSheet } from "@/ui";
import { copy } from "./api.ts";
import type { Draft } from "./draft.ts";
import { warningsText } from "./source-warnings.ts";

/**
 * ⋯ › Save as copy (D11): a new dashboard from the current version plus any unsaved edits, opened
 * in edit mode. This dashboard stays as it was saved; the edits move to the copy.
 */
const props = defineProps<{ missionId: MissionId; dashboardId: DashboardId; name: string }>();
const emit = defineEmits<{ copied: [] }>();
const router = useRouter();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const title = ref("");
const draft = ref<Draft | null>(null);
const error = ref<string | null>(null);
const busy = ref(false);
/** A copy that went through with source warnings: say them here, then open it on request. */
const copied = ref<{ id: string; note: string } | null>(null);
function open(from: Draft) {
  draft.value = from;
  title.value = `${props.name} (copy)`;
  error.value = null;
  copied.value = null;
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
  emit("copied");
  const note = warningsText("Copied.", result.value.warnings);
  if (!note) {
    openCopy(result.value.id);
    return;
  }
  copied.value = { id: result.value.id, note };
  // Save copy and edit is gone; Open the copy takes its place and focus (a11y A5).
  await nextTick();
  document.querySelector<HTMLElement>("[data-open-copy]")?.focus();
}
function openCopy(id: string) {
  sheet.value?.close();
  void router.push({ name: "ops.dashboard", params: { dashboardId: id }, query: { edit: "1" } });
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" title="Save as copy" initial-focus="input">
    <ApCallout v-if="copied" tone="caution" role="alert">{{ copied.note }}</ApCallout>
    <div v-else class="flex flex-col gap-3">
      <ApField v-model="title" label="Name" required />
      <p v-if="draft?.commands.length" class="m-0 text-sm text-text-3">
        The copy includes your {{ draft.commands.length }} unsaved
        {{ draft.commands.length === 1 ? "change" : "changes" }}. This dashboard stays as it was
        saved.
      </p>
      <ApCallout v-if="error" tone="crit">{{ error }}</ApCallout>
    </div>
    <template #footer>
      <ApButton variant="secondary" class="mr-auto" @click="sheet?.close()">{{
        copied ? "Close" : "Cancel"
      }}</ApButton>
      <ApButton v-if="copied" variant="primary" data-open-copy @click="openCopy(copied.id)"
        >Open the copy</ApButton
      >
      <ApButton
        v-else
        variant="primary"
        :disabled="busy || !title.trim()"
        disabled-reason="Give it a name."
        @click="submit"
        >Save copy and edit</ApButton
      >
    </template>
  </ApSheet>
</template>
