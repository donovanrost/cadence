<script setup lang="ts">
import { computed } from "vue";
import type { ConfigurationDocument, ConfigurationSnapshot, WorkspaceKey } from "./api.ts";
import ComparisonTable from "./ComparisonTable.vue";
import DraftFields from "./DraftFields.vue";
import SettingsPanel from "./SettingsPanel.vue";
import SetupSteps from "./SetupSteps.vue";
import SwitchesPanel from "./SwitchesPanel.vue";

/**
 * U94's sections over the draft as edited (#595a): the steps, the comparison and the overview
 * read the edited document; Catalog & applications and Communications are forms for someone who
 * can change the configuration, else the read-only key/value view.
 */
const props = defineProps<{
  snapshot: ConfigurationSnapshot;
  doc: ConfigurationDocument;
  section: WorkspaceKey["section"];
  workspace: WorkspaceKey | null;
  editable: boolean;
  errors: Readonly<Record<string, string>>;
}>();
const emit = defineEmits<{
  edit: [patch: Partial<ConfigurationDocument>];
  invalid: [count: number];
}>();
const shown = computed(() => ({ ...props.snapshot, document: props.doc }));
const form = computed(() =>
  props.editable &&
  props.workspace &&
  (props.section === "catalog" || props.section === "communications")
    ? props.section
    : null,
);
</script>

<template>
  <SetupSteps :snapshot="shown" />
  <ComparisonTable v-if="section === 'changes'" :snapshot="shown" />
  <DraftFields
    v-else-if="form === 'communications' && workspace"
    :workspace="workspace"
    :snapshot="snapshot"
    :doc="doc"
    show="communications"
    :errors="errors"
    @edit="emit('edit', $event)"
    @invalid="emit('invalid', $event)"
  />
  <SettingsPanel v-else-if="section === 'communications'" :snapshot="shown" show="communications" />
  <div v-else class="grid grid-cols-1 gap-3 console:grid-cols-[minmax(0,1fr)_360px]">
    <DraftFields
      v-if="form === 'catalog' && workspace"
      :workspace="workspace"
      :snapshot="snapshot"
      :doc="doc"
      show="catalog"
      :errors="errors"
      @edit="emit('edit', $event)"
    />
    <SettingsPanel v-else :snapshot="shown" :show="section === 'overview' ? 'all' : 'catalog'" />
    <SwitchesPanel :snapshot="snapshot" />
  </div>
</template>
