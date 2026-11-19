<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { useInPlaceSwap } from "@/ui";
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
// a11y A1/A5: Edit swaps in SectionEditor (focus its first field); Cancel swaps back to Edit.
const root = ref<HTMLElement | null>(null);
const edit = useInPlaceSwap(root, {
  open: computed({
    get: () => editing.value === props.section.key,
    set: (on) => (editing.value = on ? props.section.key : null),
  }),
});
</script>

<template>
  <div ref="root" class="contents">
    <SectionEditor
      v-if="editing === section.key"
      data-swap-editor
      :mission-id="missionId"
      :profile="detail.profile"
      :section="section"
      :staged="staged"
      @cancel="edit.hide()"
    />
    <SchemaSectionPanel
      v-else
      :section="section"
      :inherit-count="detail.inherit_count"
      :framing-off="framingOff"
      :staged="staged"
      :can-edit="canEdit()"
      @edit="edit.show"
    />
  </div>
</template>
