<script setup lang="ts">
import CadenceSettingsSection from "@cadence/ui/CadenceSettingsSection.vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceLink from "@cadence/ui/CadenceLink.vue";
import CadenceTableFrame from "@cadence/ui/CadenceTableFrame.vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import ApprovalJourney from "./ApprovalJourney.vue";
import { actors, approvalNames, scopeNames, settingsPath, spacecraftNames } from "./fixtures";
import type { SettingsStudy } from "./state";
defineProps<{ study: SettingsStudy }>();
</script>
<template>
  <div class="st-activation st-stack">
    <div class="st-section-heading">
      <span class="hero-rocket-launch st-large-icon" aria-hidden="true" />
      <div>
        <h2>{{ spacecraftNames[study.activeMission.value] }} · Review configuration</h2>
        <p>Saved revision 5 · {{ scopeNames[study.activeMission.value] }}</p>
      </div>
      <span class="st-tag">{{
        study.currentActivation.value.status === "active" ? "Active" : "Ready for review"
      }}</span>
    </div>
    <div class="st-source">
      <span class="hero-adjustments-horizontal st-icon" aria-hidden="true" />
      <div>
        <strong>{{ approvalNames[study.savedApproval.value] }}</strong
        ><span>Uses the saved settings for {{ scopeNames[study.activeMission.value] }}</span>
      </div>
      <CadenceLink :href="settingsPath(study.activeMission.value)"
        >View approval setting</CadenceLink
      >
    </div>
    <CadenceSettingsSection
      title="Proposed changes"
      description="This saved revision updates the catalog used by Telemetry Decom and Commanding."
      ><CadenceTableFrame
        ><thead>
          <tr>
            <th>Configuration</th>
            <th>Active</th>
            <th>Saved revision 5</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <th>Onboard computer catalog</th>
            <td>Kestrel FSW · r3.3</td>
            <td>Kestrel FSW · r3.4</td>
          </tr>
          <tr>
            <th>Command definitions</th>
            <td>18</td>
            <td>19 · adds CAPTURE_IMAGE</td>
          </tr>
          <tr>
            <th>Telemetry input</th>
            <td>OBC downlink · VC 0</td>
            <td>Unchanged</td>
          </tr>
        </tbody></CadenceTableFrame
      ><template #footer
        ><span class="st-inline"
          ><span class="hero-check-circle st-icon" aria-hidden="true" /> Catalog approved · Replay
          qualified · Input connected</span
        ></template
      ></CadenceSettingsSection
    >
    <ApprovalJourney :approval="study.savedApproval.value" />
    <div
      v-if="study.currentActivation.value.status === 'active'"
      class="st-completion"
      role="status"
    >
      <span class="hero-check-circle st-large-icon" aria-hidden="true" />
      <div>
        <h3>Configuration activated</h3>
        <p>
          Revision 5 is active for {{ spacecraftNames[study.activeMission.value] }}.
          {{ actors[study.currentActivation.value.executor] }}
          {{
            study.currentActivation.value.approval === "independent"
              ? "approved and activated"
              : "reviewed and activated"
          }}
          the change.
        </p>
        <small>Simulated activation · No spacecraft was changed.</small>
      </div>
    </div>
    <CadenceSettingsSection
      v-else-if="study.currentActivation.value.status === 'pending'"
      title="Independent review"
      description="Review this saved revision and record your decision."
    >
      <div
        v-if="study.currentActivation.value.requester === study.actor.value"
        class="st-pending"
        role="status"
      >
        <span class="hero-user-group st-large-icon" aria-hidden="true" />
        <div>
          <strong>Waiting for another reviewer</strong>
          <p>You submitted this revision. Another authorized person must approve it.</p>
          <small>Use the study controls below to explore the reviewer’s view.</small>
        </div>
      </div>
      <form
        v-else
        id="settings-study-review"
        class="st-review-form"
        @submit.prevent="study.decide(true)"
      >
        <p>Submitted by {{ actors[study.currentActivation.value.requester] }} · Saved revision 5</p>
        <CadenceField label="Decision rationale" control-id="settings-review-rationale">
          <textarea
            id="settings-review-rationale"
            v-model="study.rationale.value"
            class="textarea w-full"
            required
            maxlength="4096"
            rows="3"
            placeholder="Record what you checked and why this change is ready."
          />
        </CadenceField>
        <div class="st-actions">
          <CadenceButton
            variant="danger"
            size="sm"
            :disabled="!study.rationale.value.trim()"
            @click="study.decide(false)"
            >Reject</CadenceButton
          ><CadenceButton
            variant="primary"
            size="sm"
            type="submit"
            :disabled="!study.rationale.value.trim()"
            >Approve and activate</CadenceButton
          >
        </div>
      </form>
    </CadenceSettingsSection>
    <div v-else class="st-activation-action">
      <div>
        <h3>
          {{
            study.currentActivation.value.status === "stale"
              ? "Approval settings changed"
              : study.currentActivation.value.status === "rejected"
                ? "Review rejected"
                : "Ready to proceed"
          }}
        </h3>
        <p v-if="study.currentActivation.value.status === 'stale'">
          Review the current requirement before submitting this saved revision again.
        </p>
        <p v-else-if="study.currentActivation.value.status === 'rejected'">
          {{ actors[study.currentActivation.value.reviewer] }}:
          {{ study.currentActivation.value.reason }}
        </p>
        <p v-else>
          {{
            study.savedApproval.value === "direct"
              ? "You can activate this exact saved revision after reviewing the changes above."
              : "Submit this exact saved revision for another authorized person to review."
          }}
        </p>
      </div>
      <CadenceButton size="sm" variant="primary" @click="study.activateOrSubmit">{{
        study.savedApproval.value === "direct" ? "Activate configuration" : "Submit for review"
      }}</CadenceButton>
    </div>
    <details class="st-simulation">
      <summary>Study controls · Acting as {{ actors[study.actor.value] }}</summary>
      <p>
        These sample people can review and activate configurations. A submitted change requires a
        different person only when the saved setting requires independent approval.
      </p>
      <div class="st-actions">
        <CadenceButton
          size="sm"
          :aria-pressed="study.actor.value === 'maya'"
          @click="study.actor.value = 'maya'"
          >Act as Maya Chen</CadenceButton
        ><CadenceButton
          size="sm"
          :aria-pressed="study.actor.value === 'eli'"
          @click="study.actor.value = 'eli'"
          >Act as Eli Navarro</CadenceButton
        >
      </div>
    </details>
  </div>
</template>
