<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ApButton, ApEmptyState, ApKeyValue, ApPanel, useNow } from "@/ui";
import ChecksPanel from "./ChecksPanel.vue";
import OperationPanel from "./OperationPanel.vue";
import OrbitSection from "./orbit/OrbitSection.vue";
import RoutingRulesPanel from "./RoutingRulesPanel.vue";
import { identityFacts, type SpacecraftDetail } from "./detail.ts";

/** Readiness, identity, pinned profile, routing, operation switches and orbit for one spacecraft. */
defineProps<{ missionId: MissionId; detail: SpacecraftDetail; canStage: boolean }>();
const now = useNow();
</script>

<template>
  <div class="grid grid-cols-1 items-start gap-4 xl:grid-cols-2">
    <ChecksPanel :checks="detail.readiness.checks" />
    <div class="flex flex-col gap-4">
      <ApPanel index="D2" title="Identity">
        <ApKeyValue :items="identityFacts(detail, now)" :columns="2" />
      </ApPanel>
      <ApPanel index="D3" title="Profile & version">
        <ApEmptyState
          v-if="detail.profile === null"
          state="off"
          headline="No profile"
          sentence="A spacecraft takes its framing, catalog and routing from the profile it pins."
        />
        <div v-else class="flex flex-wrap items-center justify-between gap-3">
          <span class="text-base text-readout"
            >{{ detail.profile.name ?? "Deleted profile" }}
            <span class="font-mono text-sm text-text-4">pinned v{{ detail.profile.version }}</span>
            <span
              v-if="
                detail.profile.latest_version !== null &&
                detail.profile.latest_version > detail.profile.version
              "
              class="text-sm text-caution-text"
            >
              · latest is v{{ detail.profile.latest_version }}</span
            ></span
          >
          <ApButton
            size="compact"
            :to="{ name: 'setup.profile', params: { profileId: detail.profile.id } }"
            >Open profile</ApButton
          >
        </div>
      </ApPanel>
    </div>
    <RoutingRulesPanel
      :mission-id="missionId"
      :spacecraft-name="detail.spacecraft.name"
      :rules="detail.routing_rules"
      :can-stage="canStage"
      class="xl:col-span-2"
    />
    <OperationPanel
      :mission-id="missionId"
      :detail="detail"
      :can-stage="canStage"
      class="xl:col-span-2"
    />
    <OrbitSection
      :mission-id="missionId"
      :spacecraft-id="detail.spacecraft.id"
      class="xl:col-span-2"
    />
  </div>
</template>
