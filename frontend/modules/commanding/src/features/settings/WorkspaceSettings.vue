<script setup lang="ts">
import { computed } from "vue";
import type { SettingsContext, SettingsSectionPort } from "@cadence/plugin-sdk/settings";
import { useSettingsSection } from "@cadence/plugin-sdk/settings-vue";
import CadenceSettingsSection from "@cadence/ui/CadenceSettingsSection.vue";
import CadenceSettingsEditorFrame from "@cadence/ui/CadenceSettingsEditorFrame.vue";
import CadenceSettingRow from "@cadence/ui/CadenceSettingRow.vue";
import CadenceSettingSource from "@cadence/ui/CadenceSettingSource.vue";
import CadenceRadioCard from "@cadence/ui/CadenceRadioCard.vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceLink from "@cadence/ui/CadenceLink.vue";
import { readWorkspaceDefault } from "./contracts";
const props = defineProps<{
  snapshot: unknown;
  context: SettingsContext;
  canEdit: boolean;
  port: SettingsSectionPort;
}>();
const editor = useSettingsSection(props, readWorkspaceDefault);
const shelf = computed(() => editor.effective.value.shelf);
const sourceLabel = computed(
  () =>
    ({
      organization: "Organization default",
      inherited: "Inherited from organization",
      overridden: "Mission override",
      enforced: "Required by organization",
    })[editor.source.value],
);
const trail = computed(() =>
  props.context.scope === "organization"
    ? props.context.organizationName
    : `${props.context.organizationName} → ${props.context.missionName}`,
);
</script>
<template>
  <CadenceSettingsEditorFrame
    :can-keep-changes="editor.editable.value"
    :dirty="editor.dirty.value"
    :busy="editor.busy.value"
    :save-disabled="!editor.editable.value || editor.conflict.value"
    :conflict="editor.conflict.value"
    :uncertain="editor.uncertain.value"
    :message="editor.message.value"
    @save="editor.save"
    @discard="editor.discard"
    @refresh="editor.refresh"
    @keep-changes="editor.keepChanges"
  >
    <template #conflict
      ><p>
        The shelf currently opens <strong>{{ editor.latest.value.effective.shelf }}</strong
        >.
      </p></template
    >
    <CadenceSettingSource :label="sourceLabel" :trail="trail">
      <CadenceLink v-if="context.scope === 'mission'" href="/settings/commanding.defaults"
        >View organization setting</CadenceLink
      >
    </CadenceSettingSource>
    <CadenceSettingsSection
      title="Workspace defaults"
      description="Give operators a consistent starting point when they open Commanding."
    >
      <CadenceSettingRow
        label="Command shelf"
        description="Choose how the stage and execution shelf opens. Operators can expand or minimize it while they work."
      >
        <fieldset class="workspace-settings-choices" :disabled="!editor.editable.value">
          <legend class="sr-only">Command shelf opening state</legend>
          <CadenceRadioCard
            name="command-shelf"
            value="expanded"
            :checked="shelf === 'expanded'"
            label="Expanded"
            description="Start with the stage and execution shelf visible."
            @select="editor.choose({ shelf: 'expanded' })"
            ><template #icon><span class="hero-view-columns" /></template
          ></CadenceRadioCard>
          <CadenceRadioCard
            name="command-shelf"
            value="minimized"
            :checked="shelf === 'minimized'"
            label="Minimized"
            description="Give command building more room."
            @select="editor.choose({ shelf: 'minimized' })"
            ><template #icon><span class="hero-bars-3-bottom-left" /></template
          ></CadenceRadioCard>
        </fieldset>
        <template v-if="editor.source.value === 'overridden'" #detail
          ><CadenceButton
            size="xs"
            variant="quiet"
            :disabled="!editor.editable.value"
            @click="editor.reset"
            >Use organization default</CadenceButton
          ></template
        >
      </CadenceSettingRow>
      <template #footer
        >Applies when opening the workspace. Opening a stage or an execution still reveals its
        shelf.</template
      >
    </CadenceSettingsSection>
    <section
      class="workspace-settings-preview"
      aria-label="Command workspace preview"
      :data-shelf="shelf"
    >
      <div class="workspace-settings-preview__heading">
        <span class="hero-command-line" aria-hidden="true" />Commanding
        <small>Layout preview</small>
      </div>
      <div class="workspace-settings-preview__work">
        <span>Spacecraft</span>
        <div>
          <strong>Prepare a command</strong><span class="workspace-settings-placeholder" /><span
            class="workspace-settings-placeholder"
          />
        </div>
      </div>
      <div class="workspace-settings-preview__shelf">
        <strong>Command shelf</strong><span>Stage · Execution</span>
        <div v-if="shelf === 'expanded'" class="workspace-settings-placeholder" />
      </div>
    </section>
    <template #context
      ><div class="workspace-settings-context">
        <p>{{ editor.dirty.value ? "Preview after saving" : "Effective setting" }}</p>
        <h3>{{ shelf === "expanded" ? "Command shelf visible" : "More room to prepare" }}</h3>
        <p>
          This default sets the initial layout. Operators can adjust the shelf during their session.
        </p>
        <CadenceLink
          v-if="context.scope === 'mission'"
          :href="`/missions/${encodeURIComponent(context.missionId)}/ops/commands/workspace`"
          >Open Commanding</CadenceLink
        >
      </div></template
    >
    <template #history><slot name="history" /></template>
  </CadenceSettingsEditorFrame>
</template>
<style scoped>
.workspace-settings-choices {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin: 0;
  padding: 0;
  border: 0;
  min-width: 0;
}
.workspace-settings-preview {
  border: 1px solid var(--border-subtle);
  border-radius: var(--radius-md);
  overflow: hidden;
  background: var(--elevation-sunken);
}
.workspace-settings-preview__heading {
  display: flex;
  gap: 8px;
  align-items: center;
  padding: 12px 16px;
  border-bottom: 1px solid var(--border-subtle);
}
.workspace-settings-preview__heading > span {
  width: 15px;
  height: 15px;
}
.workspace-settings-preview__heading small {
  margin-left: auto;
  color: var(--text-subtle);
}
.workspace-settings-preview__work {
  display: grid;
  grid-template-columns: 100px 1fr;
  min-height: 155px;
}
.workspace-settings-preview__work > span {
  padding: 18px 12px;
  border-right: 1px solid var(--border-subtle);
  color: var(--text-subtle);
  font-size: 10px;
}
.workspace-settings-preview__work > div {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 18px;
}
.workspace-settings-placeholder {
  display: block;
  height: 7px;
  width: 80%;
  border-radius: 2px;
  background: var(--border-subtle);
}
.workspace-settings-preview__shelf {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 12px;
  padding: 14px 16px;
  border-top: 1px solid var(--border-default);
}
.workspace-settings-preview__shelf > span {
  margin-left: auto;
  font-size: 10px;
  color: var(--text-subtle);
}
[data-shelf="expanded"] .workspace-settings-preview__shelf {
  min-height: 90px;
}
.workspace-settings-context {
  display: flex;
  flex-direction: column;
  gap: 16px;
}
p {
  margin: 0;
  color: var(--text-subtle);
}
h3 {
  margin: 0;
  font-size: 13px;
}
.workspace-settings-context > p:first-child {
  font: 9px/1.6 var(--font-mono);
  text-transform: uppercase;
  letter-spacing: 0.06em;
}
</style>
