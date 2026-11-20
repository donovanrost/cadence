<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ref } from "vue";
import { failureOutcome } from "@/features/changes/index.ts";
import { ApButton, ApCallout } from "@/ui";
import type { SpacecraftId } from "@/api";
import { changeApp, type App, type AppAction } from "./api.ts";

/** Install / disable / uninstall for one app, through the app-change seam. */
const props = defineProps<{ missionId: MissionId; app: App; spacecraftId?: SpacecraftId | null }>();
const emit = defineEmits<{ changed: [] }>();
const busy = ref(false);
/** `failed`: the act was refused or failed, said as an alert; "Staged" is read politely (B6, ux #276). */
const note = ref<{ text: string; failed: boolean } | null>(null);

async function run(action: AppAction) {
  busy.value = true;
  note.value = null;
  try {
    const outcome = await changeApp(
      props.missionId,
      props.app.key,
      action,
      props.spacecraftId ?? null,
    );
    if (outcome.kind === "failed")
      note.value = { text: failureOutcome(outcome.error, "changed").sentence, failed: true };
    else if (outcome.kind === "staged")
      note.value = { text: "Staged. It applies with the change set.", failed: false };
    emit("changed");
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div class="flex flex-col items-end gap-2">
    <div class="flex gap-2">
      <ApButton
        v-if="app.state === 'not_installed'"
        size="compact"
        :disabled="busy"
        disabled-reason="Working…"
        @click="run('install')"
        >Install</ApButton
      >
      <ApButton
        v-if="app.state === 'installed'"
        size="compact"
        variant="ghost"
        :disabled="busy"
        disabled-reason="Working…"
        @click="run('disable')"
        >Disable</ApButton
      >
      <ApButton
        v-if="app.state === 'disabled'"
        size="compact"
        :disabled="busy"
        disabled-reason="Working…"
        @click="run('install')"
        >Enable</ApButton
      >
      <ApButton
        v-if="app.state === 'disabled'"
        size="compact"
        variant="danger"
        :disabled="busy"
        disabled-reason="Working…"
        @click="run('uninstall')"
        >Uninstall</ApButton
      >
    </div>
    <ApCallout v-if="note" tone="caution" :role="note.failed ? 'alert' : 'status'">{{
      note.text
    }}</ApCallout>
  </div>
</template>
