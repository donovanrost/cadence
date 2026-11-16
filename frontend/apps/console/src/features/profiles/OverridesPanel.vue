<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ref } from "vue";
import { ApButton, ApCallout, ApEmptyState, ApPanel, useInPlaceSwap } from "@/ui";
import OverrideCreate from "./OverrideCreate.vue";
import OverridesList from "./OverridesList.vue";
import type { ProfileDetail } from "./detail.ts";

/**
 * P3 Overrides: the spacecraft that differ from the profile, Reset, and Add override. Catalog and
 * framing overrides don't depend on the routing model (qa #65); only routing overrides wait for it.
 */
defineProps<{ missionId: MissionId; detail: ProfileDetail; canStage: boolean }>();
// a11y A1/A5: Add override swaps in the form above the panel; focus its first field, and on Cancel
// return to Add override. (B1: focus moves into the form, so Tab runs on from there.)
const root = ref<HTMLElement | null>(null);
const add = useInPlaceSwap(root);
const adding = add.open;
</script>

<template>
  <div ref="root" class="contents">
    <OverrideCreate
      v-if="adding"
      data-swap-editor
      :mission-id="missionId"
      :detail="detail"
      @cancel="add.hide()"
    />
    <ApPanel
      index="P3"
      title="Overrides"
      :meta="`${detail.override_count} of ${detail.inherit_count} differ`"
      flush
    >
      <template v-if="canStage && !adding" #header>
        <ApButton size="compact" data-swap-opener @click="add.show">Add override</ApButton>
      </template>
      <ApCallout v-if="detail.routing_model === 'per_spacecraft'" tone="info">
        This profile's spacecraft set their own routing, so routing isn't overridden here. Catalog
        and framing overrides work.
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
  </div>
</template>
