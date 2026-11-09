<script setup lang="ts">
import {
  ApButton,
  ApEmptyState,
  ApListRow,
  ApPanel,
  ApStatTile,
  ApTable,
  plural,
  type ApColumn,
} from "@/ui";
import { ruleText, sortedTemplates, type PlanningSummary } from "./api.ts";

/** Requirements tab: coverage (P1), templates with the rule in words (P2), not covered (P3). */
defineProps<{ summary: PlanningSummary }>();
const columns: readonly ApColumn[] = [
  { key: "name", label: "Template" },
  { key: "applies_to", label: "Applies to" },
  { key: "rule", label: "Rule", mono: true },
  { key: "priority", label: "Priority" },
  { key: "version", label: "Version", mono: true },
  { key: "count", label: "Spacecraft", mono: true, align: "end" },
];
</script>

<template>
  <div class="grid grid-cols-2 gap-px border border-hairline bg-hairline md:grid-cols-4">
    <ApStatTile
      label="Spacecraft covered"
      :value="summary.coverage.covered"
      :denominator="summary.coverage.spacecraft_total"
      :state="summary.coverage.covered < summary.coverage.spacecraft_total ? 'caution' : 'neutral'"
    />
    <ApStatTile label="Templates" :value="summary.templates.length" />
    <ApStatTile
      label="Contacts per day"
      :value="summary.coverage.contacts_per_day"
      :caption="summary.coverage.contacts_per_day === null ? 'not computed yet' : undefined"
    />
    <ApStatTile
      label="Uplink passes per day"
      :value="summary.coverage.uplink_passes_per_day"
      :caption="summary.coverage.uplink_passes_per_day === null ? 'not computed yet' : undefined"
    />
  </div>
  <ApPanel index="P2" title="Templates" flush>
    <template v-if="summary.permissions.includes('planning.edit')" #header>
      <ApButton
        size="compact"
        variant="primary"
        :to="{ name: 'setup.contact-planning.template', params: { templateId: 'new' } }"
        >New template</ApButton
      >
    </template>
    <ApEmptyState
      v-if="summary.templates.length === 0"
      state="off"
      headline="No contact rules yet"
      sentence="A template says how often each spacecraft it applies to must be heard."
    />
    <ApTable
      v-else
      :columns="columns"
      :rows="sortedTemplates(summary.templates)"
      :row-key="(t) => t.id"
      caption="Requirement templates"
    >
      <template #cell-name="{ row }">
        <RouterLink
          :to="{ name: 'setup.contact-planning.template', params: { templateId: row.id } }"
          class="font-semibold text-readout no-underline hover:text-bright hover:underline max-md:hit-44"
          >{{ row.name }}</RouterLink
        >
      </template>
      <template #cell-rule="{ row }">{{ ruleText(row.rule_summary) }}</template>
      <template #cell-priority="{ row }"
        ><span class="capitalize" :class="row.priority === 'critical' ? 'text-caution-text' : ''">{{
          row.priority
        }}</span></template
      >
      <template #cell-version="{ row }">v{{ row.version }}</template>
      <template #cell-count="{ row }">{{ row.applies_to_count }}</template>
    </ApTable>
  </ApPanel>
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
