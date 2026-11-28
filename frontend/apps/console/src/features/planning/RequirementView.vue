<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, nextTick, ref, watch } from "vue";
import { useRemoteQuery } from "@/api";
import {
  ApCallout,
  ApKeyValue,
  ApPanel,
  ApRemote,
  ApTable,
  formatAbsolute,
  refocusFirst,
  plural,
} from "@/ui";
import type { ApColumn } from "@/ui";
import { fetchTemplate } from "./api.ts";
import RequirementEnd from "./RequirementEnd.vue";
import RequirementPlanning from "./RequirementPlanning.vue";
import {
  endedLine,
  fetchRequirementSchema,
  occurrenceDay,
  requirementFacts,
  type RequirementDetail,
} from "./requirements.ts";
import VersionByCell from "./VersionByCell.vue";

/** P4 requirement, read: its facts, how it ended, where a template's lives, and its versions. */
const props = defineProps<{
  missionId: MissionId;
  requirement: RequirementDetail;
  endable: boolean;
  canEdit: boolean;
}>();
const emit = defineEmits<{ ended: [] }>();
/**
 * #244 (A5): a successful Close or Cancel unmounts RequirementEnd (its confirm had focus) once the
 * refetch shows it ended. Focus moves to the ended line when it appears.
 */
const endedBox = ref<HTMLElement | null>(null);
let justEnded = false;
function onEnded() {
  justEnded = true;
  emit("ended");
}
// fe-ops on #584: a pending move never outlives the requirement it was for.
watch(
  () => props.requirement.id,
  () => (justEnded = false),
);
watch(
  () => endedLine(props.requirement),
  async (line) => {
    if (!line || !justEnded) return;
    justEnded = false;
    await nextTick();
    // B4 (ux's #431 rule): only when focus was lost (the kit's refocusFirst).
    refocusFirst(endedBox.value);
  },
);
const schema = useRemoteQuery(() => props.missionId, fetchRequirementSchema);
const template = useRemoteQuery(
  () =>
    props.requirement.template_id
      ? { missionId: props.missionId, templateId: props.requirement.template_id }
      : null,
  fetchTemplate,
);
const templateName = computed(() =>
  template.state.value.status === "ready" ? template.state.value.value.name : "its template",
);
/** A template's occurrence closes or cancels alone (ux): the sheet names its day and template. */
const occurrence = computed(() => {
  const day = props.requirement.template_id ? occurrenceDay(props.requirement.content) : null;
  return day ? { day, template: templateName.value } : null;
});
const columns: readonly ApColumn[] = [
  { key: "version", label: "Version", mono: true },
  { key: "at", label: "Created", mono: true },
  { key: "by", label: "By" },
];
</script>

<template>
  <div v-if="endedLine(requirement)" ref="endedBox" tabindex="-1" data-ended-line>
    <ApCallout tone="off">{{ endedLine(requirement) }}</ApCallout>
  </div>
  <ApCallout v-if="requirement.template_id" tone="info"
    >Change it in its template:
    <RouterLink
      :to="{
        name: 'setup.contact-planning.template',
        params: { templateId: requirement.template_id },
      }"
      class="text-readout underline underline-offset-2"
      >{{ templateName }}</RouterLink
    >.</ApCallout
  >
  <ApPanel index="Q1" title="Requirement">
    <ApRemote :state="schema.state.value" loading-label="Loading…" @retry="schema.refetch">
      <template #default="{ value: s }">
        <ApKeyValue :items="requirementFacts(s, requirement)" :columns="2" />
      </template>
    </ApRemote>
  </ApPanel>
  <RequirementPlanning :requirement="requirement" />
  <RequirementEnd
    v-if="endable"
    :mission-id="missionId"
    :requirement="requirement"
    :occurrence="occurrence"
    @ended="onEnded"
  />
  <ApPanel index="Q2" title="History" :meta="plural(requirement.versions.length, 'version')" flush>
    <ApTable
      :columns="columns"
      :rows="requirement.versions"
      :row-key="(v) => String(v.version)"
      caption="Requirement versions"
    >
      <template #cell-version="{ row }">v{{ row.version }}</template>
      <template #cell-at="{ row }">{{ formatAbsolute(new Date(row.created_at)) }}</template>
      <template #cell-by="{ row }"><VersionByCell :actor="row.actor" /></template>
    </ApTable>
  </ApPanel>
  <p v-if="!canEdit" class="m-0 text-sm text-text-3">Mission operators change requirements.</p>
</template>
