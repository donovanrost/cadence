<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { KindEditor } from "@/features/changes/index.ts";
import type { SpacecraftDetail } from "./detail.ts";
import { pairProfile, spacecraftDocument, withPinnedProfile } from "./edit.ts";

/** L17 Edit: the spacecraft kind's schema form, prefilled from this detail; stages a diff. */
defineProps<{ missionId: MissionId; detail: SpacecraftDetail }>();
</script>

<template>
  <KindEditor
    :mission-id="missionId"
    kind="spacecraft"
    :entity-id="detail.spacecraft.id"
    :document="spacecraftDocument(detail)"
    :name="detail.spacecraft.name"
    index="D6"
    surface="spacecraft"
    :done="{ name: 'setup.spacecraft.one', params: { spacecraftId: detail.spacecraft.id } }"
    :prepare="withPinnedProfile(detail)"
    :finish="pairProfile(detail)"
  />
</template>
