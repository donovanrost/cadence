<script setup lang="ts">
import { ApTable, ApTag, formatShort, type ApColumn } from "@/ui";
import { ruleText, type TemplateRow } from "./api.ts";
import { windowText, type RequirementRow } from "./requirements.ts";

/** P4 rows (ux): spacecraft (→ the requirement), window, rule, state, source, updated. */
const props = defineProps<{ rows: readonly RequirementRow[]; templates: readonly TemplateRow[] }>();
const columns: readonly ApColumn[] = [
  { key: "spacecraft", label: "Spacecraft" },
  { key: "window", label: "Window", mono: true },
  { key: "rule", label: "Rule", mono: true },
  { key: "state", label: "State" },
  { key: "source", label: "Source" },
  { key: "updated", label: "Updated", mono: true },
];
const templateName = (id: string) => props.templates.find((t) => t.id === id)?.name ?? "Template";
</script>

<template>
  <ApTable :columns="columns" :rows="rows" :row-key="(r) => r.id" caption="Contact requirements">
    <template #cell-spacecraft="{ row }">
      <RouterLink
        :to="{ name: 'setup.contact-planning.requirement', params: { requirementId: row.id } }"
        class="font-semibold text-readout no-underline hover:text-bright hover:underline max-md:hit-44"
        >{{ row.spacecraft.name ?? row.spacecraft.id }}</RouterLink
      >
    </template>
    <template #cell-window="{ row }">{{ windowText(row.content) }}</template>
    <template #cell-rule="{ row }">{{
      row.rule_summary ? ruleText(row.rule_summary) : "—"
    }}</template>
    <template #cell-state="{ row }">
      <ApTag v-if="row.state === 'active'" state="nominal" label="Active" />
      <ApTag v-else state="off" :label="row.state === 'closed' ? 'Closed' : 'Canceled'" />
    </template>
    <template #cell-source="{ row }">
      <RouterLink
        v-if="row.template_id"
        :to="{ name: 'setup.contact-planning.template', params: { templateId: row.template_id } }"
        class="text-readout hover:underline"
        >{{ templateName(row.template_id) }}</RouterLink
      >
      <span v-else class="text-text-2">One-off</span>
    </template>
    <template #cell-updated="{ row }">{{ formatShort(new Date(row.updated_at)) }}</template>
  </ApTable>
</template>
