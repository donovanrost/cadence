<script setup lang="ts">
import { computed } from "vue";
import type { SettingsContext, SettingsSectionPort } from "@cadence/plugin-sdk/settings";
import { useSettingsSection } from "@cadence/plugin-sdk/settings-vue";
import CadenceSettingsSection from "@cadence/ui/CadenceSettingsSection.vue";
import CadenceSettingsEditorFrame from "@cadence/ui/CadenceSettingsEditorFrame.vue";
import CadenceSettingRow from "@cadence/ui/CadenceSettingRow.vue";
import CadenceSettingSource from "@cadence/ui/CadenceSettingSource.vue";
import CadenceRadioCard from "@cadence/ui/CadenceRadioCard.vue";
import CadenceCheckbox from "@cadence/ui/CadenceCheckbox.vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceLink from "@cadence/ui/CadenceLink.vue";
import CadenceTableFrame from "@cadence/ui/CadenceTableFrame.vue";
import {
  approvalNames,
  readApprovalValue,
  readMissionImpact,
  type ApprovalValue,
} from "./contracts";
const props = defineProps<{
  snapshot: unknown;
  context: SettingsContext;
  canEdit: boolean;
  port: SettingsSectionPort;
}>();
const editor = useSettingsSection(props, readApprovalValue);
const approval = computed(() => editor.effective.value.approval_requirement);
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
const impact = computed(() =>
  props.context.scope === "organization" ? readMissionImpact(props.snapshot) : null,
);
function choose(requirement: ApprovalValue["approval_requirement"]) {
  editor.choose({ approval_requirement: requirement });
  if (requirement === "direct") editor.allowOverrides(true);
}
function missionApproval(override: ApprovalValue | null) {
  return editor.draft.value.allowOverride && override
    ? override.approval_requirement
    : approval.value;
}
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
        Current saved requirement:
        <strong>{{ approvalNames[editor.latest.value.effective.approval_requirement] }}</strong
        >.
      </p></template
    >
    <CadenceSettingSource
      :label="sourceLabel"
      :trail="trail"
      :muted="editor.source.value === 'enforced'"
    >
      <CadenceLink v-if="context.scope === 'mission'" href="/settings/cadence.governance"
        >View organization setting</CadenceLink
      >
    </CadenceSettingSource>
    <CadenceSettingsSection
      title="Activation approvals"
      description="Choose how a saved spacecraft configuration is reviewed before it becomes active."
    >
      <template #status><span class="governance-tag">Cadence</span></template>
      <CadenceSettingRow
        label="Approval requirement"
        description="An authorized operator always reviews the exact saved revision. Choose whether another person must approve it."
      >
        <template #source>{{
          editor.source.value === "inherited" ? "Using the organization default" : sourceLabel
        }}</template>
        <fieldset class="governance-choices" :disabled="!editor.editable.value">
          <legend class="sr-only">Approval requirement</legend>
          <CadenceRadioCard
            name="approval-mode"
            value="direct"
            :checked="approval === 'direct'"
            label="One authorized operator"
            description="Review and activate your own changes."
            @select="choose('direct')"
            ><template #icon><span class="hero-user" /></template
          ></CadenceRadioCard>
          <CadenceRadioCard
            name="approval-mode"
            value="independent"
            :checked="approval === 'independent'"
            label="Independent approval"
            description="Another authorized person must approve."
            @select="choose('independent')"
            ><template #icon><span class="hero-user-group" /></template
          ></CadenceRadioCard>
        </fieldset>
        <template
          v-if="editor.source.value === 'enforced' || editor.source.value === 'overridden'"
          #detail
        >
          <p v-if="editor.source.value === 'enforced'">
            {{ context.organizationName }} requires this setting. It can be changed in organization
            settings by someone permitted to manage governance.
          </p>
          <CadenceButton
            v-else
            size="xs"
            variant="quiet"
            :disabled="!editor.editable.value"
            @click="editor.reset"
            >Use organization default</CadenceButton
          >
        </template>
      </CadenceSettingRow>
      <CadenceSettingRow
        v-if="context.scope === 'organization'"
        label="Mission flexibility"
        description="Let missions adapt this default, or require independent approval throughout the organization."
      >
        <CadenceCheckbox
          v-if="approval === 'independent'"
          id="allow-mission-overrides"
          :model-value="editor.draft.value.allowOverride"
          :disabled="!editor.editable.value"
          @update:model-value="editor.allowOverrides"
          >Allow missions to override this requirement</CadenceCheckbox
        >
        <p v-else>Each mission can choose to require independent approval.</p>
      </CadenceSettingRow>
      <template #footer>Validation and activation history apply in both modes.</template>
    </CadenceSettingsSection>
    <section class="governance-workflow" aria-labelledby="activation-journey-heading">
      <div class="governance-heading">
        <h3 id="activation-journey-heading">
          {{ editor.dirty.value ? "After saving" : "The activation journey" }}
        </h3>
        <span class="governance-tag">{{ approval === "direct" ? "1 operator" : "2 people" }}</span>
      </div>
      <ol class="governance-journey" aria-label="Activation steps">
        <li>
          <span class="hero-document-text" aria-hidden="true" /><strong>Prepare</strong
          ><small>Save a revision</small>
        </li>
        <li>
          <span
            :class="approval === 'direct' ? 'hero-user' : 'hero-user-group'"
            aria-hidden="true"
          /><strong>{{ approval === "direct" ? "Review" : "Independent review" }}</strong
          ><small>{{ approval === "direct" ? "The same operator" : "A different person" }}</small>
        </li>
        <li>
          <span class="hero-bolt" aria-hidden="true" /><strong>Activate</strong
          ><small>Apply the revision</small>
        </li>
      </ol>
    </section>
    <CadenceSettingsSection
      v-if="impact"
      title="Across your missions"
      :description="
        editor.dirty.value
          ? 'Preview of the requirements after saving these organization settings.'
          : 'The effective requirement for each mission.'
      "
    >
      <CadenceTableFrame
        ><thead>
          <tr>
            <th>Mission</th>
            <th>Approval requirement</th>
            <th>Source</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="mission in impact.items" :key="mission.id">
            <td>
              <CadenceLink
                :href="`/missions/${encodeURIComponent(mission.id)}/settings/cadence.governance`"
                >{{ mission.name }}</CadenceLink
              >
            </td>
            <td>{{ approvalNames[missionApproval(mission.override)] }}</td>
            <td>
              {{
                !editor.draft.value.allowOverride
                  ? "Required"
                  : mission.override
                    ? "Mission override"
                    : "Organization default"
              }}
            </td>
          </tr>
        </tbody></CadenceTableFrame
      >
      <template #footer
        >{{ impact.items.length }} of {{ impact.total }} missions shown. Organization settings apply
        to all missions.</template
      >
    </CadenceSettingsSection>
    <template #context
      ><div class="governance-context">
        <p class="governance-eyebrow">
          {{ editor.dirty.value ? "Preview after saving" : "Effective setting" }}
        </p>
        <span
          :class="[approval === 'direct' ? 'hero-user' : 'hero-user-group', 'governance-people']"
          aria-hidden="true"
        />
        <h3>{{ approvalNames[approval] }}</h3>
        <p>
          {{
            approval === "direct"
              ? "An authorized operator can review and activate a saved configuration."
              : "Configuration changes wait for approval from a different person."
          }}
        </p>
        <CadenceLink
          v-if="context.scope === 'mission'"
          :href="`/missions/${encodeURIComponent(context.missionId)}/spacecraft`"
          >Review spacecraft changes</CadenceLink
        >
      </div></template
    >
    <template #history><slot name="history" /></template>
  </CadenceSettingsEditorFrame>
</template>
<style scoped>
.governance-choices {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 0;
  margin: 0;
  border: 0;
  min-width: 0;
}
.governance-tag {
  display: inline-flex;
  padding: 3px 7px;
  border: 1px solid var(--border-default);
  border-radius: 4px;
  color: var(--text-subtle);
  font: 10px/1.4 var(--font-mono);
  white-space: nowrap;
}
.governance-workflow {
  padding: 18px 20px;
  border: 1px solid var(--border-subtle);
  border-radius: var(--radius-md);
  background: var(--elevation-sunken);
}
.governance-heading {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  align-items: center;
}
h3 {
  margin: 0;
  font-size: 13px;
  font-weight: 600;
}
p {
  margin: 0;
  color: var(--text-subtle);
}
.governance-journey {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 10px;
  padding: 18px 0 0;
  margin: 0;
  list-style: none;
}
.governance-journey li {
  display: flex;
  flex-direction: column;
  gap: 5px;
  position: relative;
}
.governance-journey li > span {
  display: block;
  width: 28px;
  height: 28px;
  color: var(--color-action);
  margin-bottom: 8px;
}
.governance-journey li:not(:last-child)::after {
  content: "";
  position: absolute;
  height: 1px;
  background: var(--border-strong);
  top: 14px;
  left: 42px;
  right: 8px;
}
.governance-journey small {
  color: var(--text-subtle);
}
.governance-context {
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.governance-eyebrow {
  font: 9px/1.6 var(--font-mono);
  text-transform: uppercase;
  letter-spacing: 0.06em;
}
.governance-people {
  display: block;
  width: 32px;
  height: 32px;
  color: var(--color-action);
}
</style>
