<script setup lang="ts">
import { ref } from "vue";
import { ApButton, ApCallout, ApEmptyState, ApPanel } from "@/ui";
import OverrideCreate from "./OverrideCreate.vue";
import OverridesList from "./OverridesList.vue";
import type { ProfileDetail } from "./detail.ts";

/**
 * P3 Overrides: the spacecraft that differ from the profile, Reset, and Add override. Catalog and
 * framing overrides don't depend on the routing model (qa #65); only routing overrides wait for it.
 */
defineProps<{ missionId: string; detail: ProfileDetail; canStage: boolean }>();
const adding = ref(false);
</script>

<template>
  <OverrideCreate v-if="adding" :mission-id="missionId" :detail="detail" @cancel="adding = false" />
  <ApPanel
    index="P3"
    title="Overrides"
    :meta="`${detail.override_count} of ${detail.inherit_count} differ`"
    flush
  >
    <template v-if="canStage && !adding" #header>
      <ApButton size="compact" @click="adding = true">Add override</ApButton>
    </template>
    <ApCallout v-if="detail.routing_model === 'per_spacecraft'" tone="info">
      This profile's spacecraft set their own routing, so routing isn't overridden here. Catalog and
      framing overrides work.
    </ApCallout>
    <ApEmptyState
      v-if="detail.overrides.length === 0"
      state="off"
      :headline="`All ${detail.inherit_count} spacecraft match the profile`"
    />
    <OverridesList
      v-else
      :mission-id="missionId"
      :overrides="detail.overrides"
      :fields="detail.sections.flatMap((s) => s.fields)"
      :can-stage="canStage"
    />
  </ApPanel>
</template>
