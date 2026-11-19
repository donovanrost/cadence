<script setup lang="ts">
import { ref } from "vue";
import { ApButton, ApSheet } from "@/ui";

/** Header actions while editing (ux): EDITING, the paused-values caption, Add widget, Add section, Save…, Discard. */
const props = defineProps<{ changes: number; busy: boolean }>();
const emit = defineEmits<{ add: []; addSection: []; save: []; discard: [] }>();
const confirm = ref<InstanceType<typeof ApSheet> | null>(null);
function onDiscard() {
  if (props.changes === 0) emit("discard");
  else confirm.value?.open();
}
</script>

<template>
  <div class="flex items-center gap-3">
    <span class="flex flex-col leading-tight">
      <span class="font-display text-sm uppercase tracking-tag text-caution-text">Editing</span>
      <span class="text-xs text-text-3">Live values paused while editing.</span>
    </span>
    <ApButton variant="secondary" size="compact" data-add-widget @click="emit('add')"
      >Add widget</ApButton
    >
    <ApButton variant="secondary" size="compact" data-add-section @click="emit('addSection')"
      >Add section</ApButton
    >
    <ApButton
      variant="primary"
      size="compact"
      :disabled="changes === 0 || busy"
      disabled-reason="Nothing to save yet."
      @click="emit('save')"
      >Save…</ApButton
    >
    <ApButton variant="ghost" size="compact" @click="onDiscard">Discard</ApButton>
    <ApSheet ref="confirm" title="Discard your changes?">
      <p class="m-0 text-base text-readout">
        {{ changes }} unsaved {{ changes === 1 ? "change" : "changes" }} will be lost. The dashboard
        stays as it was saved.
      </p>
      <template #footer>
        <ApButton variant="secondary" class="mr-auto" @click="confirm?.close()"
          >Keep editing</ApButton
        >
        <ApButton variant="danger" @click="(confirm?.close(), emit('discard'))"
          >Discard changes</ApButton
        >
      </template>
    </ApSheet>
  </div>
</template>
