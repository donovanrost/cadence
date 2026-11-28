<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ApListRow, ApPanel, plural } from "@/ui";
import type { PlanningSummary } from "./api.ts";
import PlanningStats from "./PlanningStats.vue";
import RequirementsPanel from "./RequirementsPanel.vue";
import TemplatesPanel from "./TemplatesPanel.vue";

/** Requirements tab: coverage (P1), templates (P2), not covered (P3), one-off requirements (P4). */
defineProps<{ summary: PlanningSummary; missionId: MissionId }>();
</script>

<template>
  <PlanningStats :summary="summary" />
  <TemplatesPanel :summary="summary" />
  <RequirementsPanel
    :mission-id="missionId"
    :templates="summary.templates"
    :can-edit="summary.permissions.includes('planning.requirement.edit')"
  />
  <ApPanel v-if="summary.not_covered.length > 0" index="P3" title="Not covered" flush>
    <ul class="m-0 list-none p-0">
      <ApListRow
        v-for="g in summary.not_covered"
        :key="`${g.group}-${g.label}`"
        state="caution"
        :title="`${plural(g.count, 'spacecraft', 'spacecraft')} in ${g.label} have no contact rule`"
      />
    </ul>
  </ApPanel>
</template>
