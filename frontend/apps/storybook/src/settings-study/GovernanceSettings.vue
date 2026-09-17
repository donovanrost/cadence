<script setup lang="ts">
import CadenceSettingsSection from "@cadence/ui/CadenceSettingsSection.vue";
import CadenceSettingRow from "@cadence/ui/CadenceSettingRow.vue";
import CadenceCheckbox from "@cadence/ui/CadenceCheckbox.vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceLink from "@cadence/ui/CadenceLink.vue";
import CadenceTableFrame from "@cadence/ui/CadenceTableFrame.vue";
import SettingsSource from "./SettingsSource.vue";
import ApprovalJourney from "./ApprovalJourney.vue";
import { approvalNames, missions, settingsPath } from "./fixtures";
import type { SettingsStudy } from "./state";
defineProps<{ study: SettingsStudy }>();
</script>
<template>
  <div class="st-stack">
    <SettingsSource :study="study" />
    <CadenceSettingsSection
      title="Activation approvals"
      description="Choose how a saved spacecraft configuration is reviewed before it becomes active."
    >
      <template #status><span class="st-tag">Cadence</span></template>
      <CadenceSettingRow
        label="Approval requirement"
        description="An authorized operator always reviews the exact saved revision. Choose whether another person must approve it."
      >
        <template #source
          ><span v-if="study.source.value === 'enforced'" class="st-inline"
            ><span class="hero-lock-closed st-icon" aria-hidden="true" /> Organization
            requirement</span
          ><span v-else>{{
            study.scope.value === "organization"
              ? "Default for missions in this organization"
              : study.source.value === "inherited"
                ? "Using the organization default"
                : "Configured for this mission"
          }}</span></template
        >
        <fieldset class="st-choices" :disabled="!study.editable.value">
          <legend class="sr-only">Approval requirement</legend>
          <label class="st-choice" :data-selected="study.approval.value === 'direct'">
            <input
              type="radio"
              name="approval-mode"
              value="direct"
              :checked="study.approval.value === 'direct'"
              @change="study.chooseApproval('direct')"
            />
            <span class="hero-user st-choice-icon" aria-hidden="true" /><span
              ><strong>One authorized operator</strong
              ><small>Review and activate your own changes.</small></span
            >
          </label>
          <label class="st-choice" :data-selected="study.approval.value === 'independent'">
            <input
              type="radio"
              name="approval-mode"
              value="independent"
              :checked="study.approval.value === 'independent'"
              @change="study.chooseApproval('independent')"
            />
            <span class="hero-user-group st-choice-icon" aria-hidden="true" /><span
              ><strong>Independent approval</strong
              ><small>Another authorized person must approve.</small></span
            >
          </label>
        </fieldset>
        <template
          v-if="study.source.value === 'enforced' || study.source.value === 'overridden'"
          #detail
        >
          <div v-if="study.source.value === 'enforced'" class="st-explanation">
            <span class="hero-lock-closed st-icon" aria-hidden="true" />
            <p>
              Flight Operations requires independent approval for every mission. This requirement
              can be changed in organization settings by someone permitted to manage governance.
            </p>
          </div>
          <div
            v-else-if="study.scope.value !== 'organization' && study.source.value === 'overridden'"
            class="st-inline st-between"
          >
            <span class="st-muted">This mission has its own requirement.</span
            ><CadenceButton
              size="xs"
              variant="quiet"
              :disabled="!study.editable.value"
              @click="study.resetToOrganization"
              >Use organization default</CadenceButton
            >
          </div>
        </template>
      </CadenceSettingRow>
      <CadenceSettingRow
        v-if="study.scope.value === 'organization'"
        label="Mission flexibility"
        description="Set a default that missions can adapt, or require independent approval throughout the organization."
      >
        <CadenceCheckbox
          v-if="study.approval.value === 'independent'"
          id="allow-mission-overrides"
          :model-value="study.organization.value.allowOverrides"
          :disabled="!study.editable.value"
          @update:model-value="study.allowOverrides"
          >Allow missions to override this requirement</CadenceCheckbox
        >
        <p v-else class="st-muted">Each mission can choose to require independent approval.</p>
      </CadenceSettingRow>
      <template #footer
        ><span class="st-inline"
          ><span class="hero-document-check st-icon" aria-hidden="true" /> Validation and activation
          history apply in both modes.</span
        ></template
      >
    </CadenceSettingsSection>
    <section class="st-workflow" aria-labelledby="activation-journey-heading">
      <div class="st-between">
        <h3 id="activation-journey-heading">
          {{ study.dirty.value ? "After saving" : "The activation journey" }}
        </h3>
        <span class="st-tag">{{
          study.approval.value === "direct" ? "1 operator" : "2 people"
        }}</span>
      </div>
      <ApprovalJourney :approval="study.approval.value" />
    </section>
    <CadenceSettingsSection
      v-if="study.scope.value === 'organization'"
      title="Across your missions"
      :description="
        study.dirty.value
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
          <tr v-for="mission in missions" :key="mission.id">
            <td>
              <CadenceLink :href="settingsPath(mission.id)">{{ mission.name }}</CadenceLink>
            </td>
            <td>{{ approvalNames[study.impact(mission.id).value] }}</td>
            <td>
              <span class="st-tag">{{
                {
                  inherited: "Organization default",
                  overridden: "Mission override",
                  enforced: "Required",
                }[study.impact(mission.id).source]
              }}</span>
            </td>
          </tr>
        </tbody></CadenceTableFrame
      >
    </CadenceSettingsSection>
  </div>
</template>
