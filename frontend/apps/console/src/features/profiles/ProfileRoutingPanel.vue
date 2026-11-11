<script setup lang="ts">
import { computed, ref } from "vue";
import { canAdministerOrganization, useMissionScope, useSession } from "@/shell";
import { ApButton, ApEmptyState, ApPanel } from "@/ui";
import OverridesPanel from "./OverridesPanel.vue";
import RuleBlock from "./RuleBlock.vue";
import RulesEditor from "./RulesEditor.vue";
import type { ProfileDetail } from "./detail.ts";

/** P2 Routing rules and P3 Overrides (DECISIONS #3, domain P2). */
const props = defineProps<{ detail: ProfileDetail; part: "routing" | "overrides" }>();
const scope = useMissionScope();
const session = useSession();
const canStage = computed(() => canAdministerOrganization(session, scope.value.organization));
const perSpacecraft = computed(() => props.detail.routing_model === "per_spacecraft");
const editing = ref(false);
</script>

<template>
  <template v-if="part === 'routing'">
    <RulesEditor
      v-if="editing"
      :mission-id="scope.mission.id"
      :detail="detail"
      @close="editing = false"
    />
    <ApPanel v-else-if="perSpacecraft" index="P2" title="Routing rule" flush>
      <ApEmptyState
        state="off"
        headline="Routing is still set per spacecraft"
        sentence="This profile has no routing rule yet. Existing per-spacecraft rules are lifted onto the profile in a reviewable change set."
      >
        <div class="flex flex-wrap gap-2">
          <ApButton v-if="canStage" size="compact" variant="primary" @click="editing = true"
            >Add a profile rule</ApButton
          >
          <ApButton size="compact" :to="{ name: 'setup.comms' }">Open comms &amp; routing</ApButton>
        </div>
      </ApEmptyState>
    </ApPanel>
    <template v-else>
      <div v-if="canStage">
        <ApButton size="compact" @click="editing = true">Edit rules</ApButton>
      </div>
      <RuleBlock
        v-for="(rule, i) in detail.rules"
        :key="rule.id"
        :rule="rule"
        :profile-name="detail.profile.name"
        :index="`P2.${i + 1}`"
      />
    </template>
  </template>
  <OverridesPanel v-else :mission-id="scope.mission.id" :detail="detail" :can-stage="canStage" />
</template>
