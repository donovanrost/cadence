<script setup lang="ts">
import { ApButton, ApEmptyState, ApPanel, ApTable, ApTag, type ApColumn } from "@/ui";
import { ruleText, sortedTemplates, type PlanningSummary } from "./api.ts";

/** P2 Templates with the rule in words (ContactPlanning.md). */
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
        <ApTag v-if="row.state === 'paused'" class="ml-2" state="caution" label="PAUSED" />
        <ApTag v-else-if="row.state === 'closed'" class="ml-2" state="off" label="CLOSED" />
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
</template>
