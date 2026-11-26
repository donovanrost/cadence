<script setup lang="ts">
import { onMounted, ref } from "vue";
import { failureOutcome } from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApField, ApSegmented } from "@/ui";
import { createShare, type DataVisibility, type SettingsKey } from "./api.ts";

/** Create share link (ux): data visibility, optional expiry date. */
const props = defineProps<{ settingsKey: SettingsKey }>();
const emit = defineEmits<{ created: []; cancel: [] }>();
const data = ref<DataVisibility>("with_data");
const expires = ref("");
const error = ref<string | null>(null);
const failure = ref<string | null>(null);
const busy = ref(false);
/** A1: focus starts on the form's first control (the chosen Data option); Esc is Cancel (A4). */
const form = ref<HTMLFormElement | null>(null);
onMounted(() => form.value?.querySelector<HTMLElement>('[tabindex="0"], input')?.focus());
const options = [
  { value: "with_data", label: "With data" },
  { value: "definition_only", label: "Definition only" },
];
const setData = (v: string) => {
  if (v === "with_data" || v === "definition_only") data.value = v;
};
async function create() {
  error.value = failure.value = null;
  // A date ends at the end of that UTC day.
  const at = expires.value.trim() === "" ? null : Date.parse(`${expires.value.trim()}T23:59:59Z`);
  if (at !== null && (Number.isNaN(at) || at <= Date.now()))
    return void (error.value = "Enter a future date like 2026-11-20, or leave it empty.");
  busy.value = true;
  try {
    const r = await createShare(props.settingsKey, {
      data_visibility: data.value,
      expires_at: at === null ? null : new Date(at).toISOString(),
    });
    if (r.ok) return void emit("created");
    failure.value = failureOutcome(r.error, "changed").sentence;
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <form
    ref="form"
    class="flex flex-col gap-3 border-b border-hairline p-4"
    @submit.prevent="create"
    @keydown.esc.stop="emit('cancel')"
  >
    <ApSegmented
      :model-value="data"
      label="Data"
      :options="options"
      @update:model-value="setData"
    />
    <p v-if="data === 'definition_only'" class="m-0 text-sm text-text-3">
      Widgets show "Data isn't shared in this link."
    </p>
    <ApField
      v-model="expires"
      label="Expires (UTC date)"
      mono
      hint="Optional. Empty means no expiry."
      :error="error"
    />
    <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
    <div class="flex gap-2">
      <ApButton type="submit" variant="primary" :disabled="busy" disabled-reason="Creating…"
        >Create share link</ApButton
      >
      <ApButton variant="ghost" @click="emit('cancel')">Cancel</ApButton>
    </div>
  </form>
</template>
