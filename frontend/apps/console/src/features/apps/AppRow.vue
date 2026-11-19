<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import type { SpacecraftId } from "@/api";
import { ApListRow, ApTag } from "@/ui";
import AppActions from "./AppActions.vue";
import type { App } from "./api.ts";

/** One app: name (a link to its pages once installed, L9), what it does or what's off without it. */
/** `spacecraftId`: the row is that spacecraft's (L19): its pages and verbs are the spacecraft's. */
defineProps<{
  missionId: MissionId;
  app: App;
  canInstall: boolean;
  spacecraftId?: SpacecraftId | null;
}>();
defineEmits<{ changed: [] }>();
const word = (a: App) =>
  a.platform
    ? "Platform · always on"
    : a.state === "installed"
      ? "Installed"
      : a.state === "disabled"
        ? "Disabled"
        : "Not set up";
</script>

<template>
  <ApListRow
    :state="app.state === 'installed' ? 'nominal' : 'off'"
    :title="app.surfaces.length > 0 && app.installed ? undefined : app.name"
    :sentence="
      app.installed
        ? (app.description ?? undefined)
        : (app.consequence_if_missing ?? app.description ?? undefined)
    "
    :meta="app.version ? `v${app.version}` : undefined"
  >
    <template v-if="app.surfaces.length > 0 && app.installed" #title>
      <RouterLink
        :to="
          spacecraftId
            ? { name: 'setup.spacecraft.app', params: { spacecraftId, appKey: app.key } }
            : { name: 'setup.app', params: { appKey: app.key } }
        "
        class="font-semibold text-readout hover:underline"
        >{{ app.name }}</RouterLink
      >
    </template>
    <template #action>
      <div class="flex flex-col items-end gap-2">
        <ApTag :state="app.state === 'installed' ? 'nominal' : 'off'" :label="word(app)" />
        <AppActions
          v-if="!app.platform && canInstall"
          :mission-id="missionId"
          :app="app"
          :spacecraft-id="spacecraftId ?? null"
          @changed="$emit('changed')"
        />
      </div>
    </template>
  </ApListRow>
</template>
