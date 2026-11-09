<script setup lang="ts">
import { computed } from "vue";
import { canAdministerOrganization, useMissionScope, useSession } from "@/shell";
import { ApButton, ApEmptyState, ApPanel } from "@/ui";
import OverridesList from "./OverridesList.vue";
import RuleBlock from "./RuleBlock.vue";
import type { ProfileDetail } from "./detail.ts";

/** P2 Routing rules and P3 Overrides (DECISIONS #3, domain P2). */
const props = defineProps<{ detail: ProfileDetail; part: "routing" | "overrides" }>();
const scope = useMissionScope();
const session = useSession();
const canStage = computed(() => canAdministerOrganization(session, scope.value.organization));
const perSpacecraft = computed(() => props.detail.routing_model === "per_spacecraft");
</script>

<template>
  <template v-if="part === 'routing'">
    <ApPanel v-if="perSpacecraft" index="P2" title="Routing rule" flush>
      <ApEmptyState
        state="off"
        headline="Routing is still set per spacecraft"
        sentence="This profile has no routing rule yet. Existing per-spacecraft rules are lifted onto the profile in a reviewable change set."
      >
        <ApButton size="compact" :to="{ name: 'setup.comms' }">Open comms &amp; routing</ApButton>
      </ApEmptyState>
    </ApPanel>
    <template v-else>
      <RuleBlock
        v-for="(rule, i) in detail.rules"
        :key="rule.id"
        :rule="rule"
        :profile-name="detail.profile.name"
        :index="`P2.${i + 1}`"
      />
    </template>
  </template>
  <ApPanel
    v-else
    index="P3"
    title="Overrides"
    :meta="`${detail.override_count} of ${detail.inherit_count} differ`"
    flush
  >
    <ApEmptyState
      v-if="perSpacecraft"
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
      :mission-id="scope.mission.id"
      :overrides="detail.overrides"
      :can-stage="canStage"
    />
  </ApPanel>
</template>
