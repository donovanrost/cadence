<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ref } from "vue";
import { ApButton } from "@/ui";
import ArchiveSheet from "./ArchiveSheet.vue";
import type { SpacecraftDetail } from "./detail.ts";

/** L17 header verbs for people who stage (config.stage): Edit (`?edit=1`) and Archive…. */
defineProps<{ missionId: MissionId; detail: SpacecraftDetail; editing: boolean }>();
const archive = ref<InstanceType<typeof ArchiveSheet> | null>(null);
</script>

<template>
  <ApButton
    v-if="!editing"
    :to="{
      name: 'setup.spacecraft.one',
      params: { spacecraftId: detail.spacecraft.id },
      query: { edit: '1' },
    }"
    >Edit</ApButton
  >
  <ApButton variant="ghost" @click="archive?.open()">Archive…</ApButton>
  <ArchiveSheet ref="archive" :mission-id="missionId" :detail="detail" />
</template>
