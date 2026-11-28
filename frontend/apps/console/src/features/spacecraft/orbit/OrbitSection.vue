<script setup lang="ts">
import type { MissionId, SpacecraftId } from "@/api";
import { useConnection } from "@/live";
import { ApCallout } from "@/ui";
import ElementSetPanel from "./ElementSetPanel.vue";
import PredictedPassesPanel from "./PredictedPassesPanel.vue";

/**
 * The spacecraft's Orbit section (#895, slice 6 of #732): D7 its element sets, D8 its predicted
 * passes. Both refresh on the mission's live changes; without the live link they say they may be
 * out of date (CLAUDE.md rule 4: stale, never nominal).
 */
defineProps<{ missionId: MissionId; spacecraftId: SpacecraftId }>();
const connection = useConnection();
</script>

<template>
  <section aria-label="Orbit" class="flex flex-col gap-4">
    <ApCallout v-if="connection === 'offline'" tone="stale">
      Live connection lost. The orbit and predicted passes may be out of date; they'll refresh when
      it's back.
    </ApCallout>
    <div class="grid grid-cols-1 items-start gap-4 xl:grid-cols-2">
      <ElementSetPanel :mission-id="missionId" :spacecraft-id="spacecraftId" />
      <PredictedPassesPanel :mission-id="missionId" :spacecraft-id="spacecraftId" />
    </div>
  </section>
</template>
