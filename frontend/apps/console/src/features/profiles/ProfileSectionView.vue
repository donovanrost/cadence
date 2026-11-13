<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import SchemaSectionPanel from "./SchemaSectionPanel.vue";
import SectionEditor from "./SectionEditor.vue";
import type { ProfileDetail, ProfileSection } from "./detail.ts";
import { editableSection } from "./sectionEdit.ts";
import type { StagedField } from "./staged.ts";

/** One schema section of the profile: read (P1) or edit with the staged aside (P1 + P4). */
const props = defineProps<{
  missionId: MissionId;
  detail: ProfileDetail;
  section: ProfileSection;
  canStage: boolean;
  framingOff: boolean;
  staged: ReadonlyMap<string, StagedField>;
}>();
const editing = defineModel<string | null>("editing", { required: true });
const canEdit = () => props.canStage && editableSection(props.section.key);
</script>

<template>
  <SectionEditor
    v-if="editing === section.key"
    :mission-id="missionId"
    :profile="detail.profile"
    :section="section"
    :staged="staged"
    @cancel="editing = null"
  />
  <SchemaSectionPanel
    v-else
    :section="section"
    :inherit-count="detail.inherit_count"
    :framing-off="framingOff"
    :staged="staged"
    :can-edit="canEdit()"
    @edit="editing = section.key"
  />
</template>
