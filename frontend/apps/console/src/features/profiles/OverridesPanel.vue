<script setup lang="ts">
import { ref } from "vue";
import { ApButton, ApEmptyState, ApPanel } from "@/ui";
import OverrideCreate from "./OverrideCreate.vue";
import OverridesList from "./OverridesList.vue";
import type { ProfileDetail } from "./detail.ts";

/** P3 Overrides: the spacecraft that differ from the profile, Reset, and Add override. */
defineProps<{ missionId: string; detail: ProfileDetail; canStage: boolean }>();
const adding = ref(false);
</script>

<template>
  <OverrideCreate
    v-if="adding"
    :mission-id="missionId"
    :detail="detail"
    @cancel="adding = false"
  />
  <ApPanel
    index="P3"
    title="Overrides"
    :meta="`${detail.override_count} of ${detail.inherit_count} differ`"
    flush
  >
    <template v-if="canStage && detail.routing_model === 'profile' && !adding" #header>
      <ApButton size="compact" @click="adding = true">Add override</ApButton>
    </template>
    <ApEmptyState
      v-if="detail.routing_model === 'per_spacecraft'"
      headline="Overrides aren't tracked yet"
      sentence="Spacecraft-level differences from the profile are recorded once routing lives on the profile."
    />
    <ApEmptyState
      v-else-if="detail.overrides.length === 0"
      state="off"
      :headline="`All ${detail.inherit_count} spacecraft match the profile`"
    />
    <OverridesList
      v-else
      :mission-id="missionId"
      :overrides="detail.overrides"
      :can-stage="canStage"
    />
  </ApPanel>
</template>
