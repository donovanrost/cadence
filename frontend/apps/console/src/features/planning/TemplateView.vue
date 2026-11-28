<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { ApKeyValue, ApPanel, ApTable, formatAbsolute, plural, type ApColumn } from "@/ui";
import { ruleText, type TemplateDetail } from "./api.ts";
import { stateChangedLine } from "./lifecycle.ts";
import TemplateLifecycle from "./TemplateLifecycle.vue";
import { fetchTemplateSchema, maxGapFact } from "./templates.ts";
import VersionByCell from "./VersionByCell.vue";

/** CP3 read view: the rule, its last lifecycle move, Pause/Resume/Close (L2), and versions. */
const props = defineProps<{ missionId: MissionId; template: TemplateDetail; canEdit: boolean }>();
// The form's schema gives the max-gap label and unit, so the page and the form say the same thing.
const schema = useRemoteQuery(() => props.missionId, fetchTemplateSchema);
const gap = computed(() => {
  const s = schema.state.value;
  return maxGapFact(s.status === "ready" ? s.value.fields : null, props.template.document);
});
const emit = defineEmits<{ moved: [] }>();
const stateWords: Readonly<Record<TemplateDetail["state"], string>> = {
  active: "Active",
  paused: "Paused",
  closed: "Closed",
  unrecognized: "Not known",
};
const facts = (t: TemplateDetail) => [
  { key: "rule", label: "Rule", value: ruleText(t.rule_summary), mono: true },
  {
    key: "applies",
    label: "Applies to",
    value: `${t.applies_to} · ${plural(t.applies_to_count, "spacecraft", "spacecraft")} now`,
  },
  { key: "priority", label: "Priority", value: t.priority.replaceAll("_", " ") },
  { key: "state", label: "State", value: stateWords[t.state] },
  ...(gap.value ? [gap.value] : []),
];
const columns: readonly ApColumn[] = [
  { key: "version", label: "Version", mono: true },
  { key: "at", label: "Created", mono: true },
  { key: "by", label: "By" },
];
</script>

<template>
  <ApPanel index="T1" title="Rule">
    <ApKeyValue :items="facts(template)" :columns="2" />
    <p v-if="stateChangedLine(template)" class="m-0 mt-3 text-sm text-text-2">
      {{ stateChangedLine(template) }}
    </p>
  </ApPanel>
  <TemplateLifecycle
    v-if="canEdit"
    :mission-id="missionId"
    :template="template"
    @moved="emit('moved')"
  />
  <ApPanel index="T2" title="History" :meta="plural(template.versions.length, 'version')" flush>
    <ApTable
      :columns="columns"
      :rows="template.versions"
      :row-key="(v) => String(v.version)"
      caption="Template versions"
    >
      <template #cell-version="{ row }">v{{ row.version }}</template>
      <template #cell-at="{ row }">{{ formatAbsolute(new Date(row.created_at)) }}</template>
      <template #cell-by="{ row }"><VersionByCell :actor="row.actor" /></template>
    </ApTable>
  </ApPanel>
  <p v-if="!canEdit" class="m-0 text-sm text-text-3">Org admins change templates.</p>
</template>
