<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from "vue";
import { ApButton, ApSheet, ApTextarea } from "@/ui";
import ChangeList from "./ChangeList.vue";
import type { VersionChange } from "./contracts.ts";

/**
 * Save drawer (Grafana-style): an optional message, the changes this save makes, and opt-in
 * "save current range / scope as default". Saving makes the new version current for everyone.
 */
const props = defineProps<{
  /** null: the preview for the current draft is pending or failed (qa: never claim "No changes"). */
  changes: readonly VersionChange[] | null;
  previewing: boolean;
  busy: boolean;
  hasScope: boolean;
}>();
const emptyText = computed(() => {
  if (props.changes) return undefined;
  return props.previewing
    ? "Listing the changes…"
    : "The change list didn't load. Saving still saves your edits.";
});
const emit = defineEmits<{
  save: [input: { message: string; defaults: { time: boolean; scope: boolean } }];
}>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const message = ref("");
const time = ref(false);
const scope = ref(false);
function open() {
  message.value = "";
  time.value = false;
  scope.value = false;
  sheet.value?.open();
}
/** Under load a save can take a minute (qa: 58 s): after 3 s, say it's still going. */
const SLOW_MS = 3_000;
const slow = ref(false);
let timer: ReturnType<typeof setTimeout> | null = null;
function stopTimer() {
  if (timer !== null) clearTimeout(timer);
  timer = null;
}
watch(
  () => props.busy,
  (busy) => {
    stopTimer();
    slow.value = false;
    if (busy) timer = setTimeout(() => (slow.value = true), SLOW_MS);
  },
);
onBeforeUnmount(stopTimer);
defineExpose({ open, close: () => sheet.value?.close() });
</script>

<template>
  <ApSheet ref="sheet" title="Save dashboard" initial-focus="textarea">
    <div class="flex flex-col gap-4">
      <ApTextarea v-model="message" label="Message (optional)" :rows="2" :maxlength="500" />
      <section class="flex flex-col gap-2">
        <h3 class="m-0 font-display text-xs uppercase tracking-label text-text-4">Changes</h3>
        <ChangeList :changes="changes ?? []" :empty="emptyText" />
      </section>
      <label class="flex items-center gap-2 text-md text-readout">
        <input
          v-model="time"
          type="checkbox"
          class="accent-[var(--color-readout)] [color-scheme:dark]"
        />
        Save the current time range as the default
      </label>
      <label v-if="hasScope" class="flex items-center gap-2 text-md text-readout">
        <input
          v-model="scope"
          type="checkbox"
          class="accent-[var(--color-readout)] [color-scheme:dark]"
        />
        Save the current spacecraft as the default
      </label>
      <p class="m-0 text-sm text-text-3">Saving makes a new version that's current for everyone.</p>
      <p v-if="slow" role="status" class="m-0 text-sm text-caution-text">
        Still saving. The server is slow right now; your edits stay in this browser until it's done.
      </p>
    </div>
    <template #footer>
      <ApButton variant="secondary" class="mr-auto" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="primary"
        :disabled="busy"
        disabled-reason="Saving…"
        @click="emit('save', { message, defaults: { time, scope } })"
        >Save</ApButton
      >
    </template>
  </ApSheet>
</template>
