<script setup lang="ts">
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceStatusSymbol from "@cadence/ui/CadenceStatusSymbol.vue";
import type { SpacecraftState } from "./state";
import { revisions, type ConfigurationChange, type SetupIssue } from "./fixtures";
defineProps<{
  spacecraft: string;
  state: SpacecraftState;
  changes: readonly ConfigurationChange[];
  issues: readonly SetupIssue[];
  unsaved: boolean;
  canReview: boolean;
  canActivate: boolean;
}>();
defineEmits<{
  repair: [issue: SetupIssue, event: MouseEvent];
  submit: [];
  approve: [];
  activate: [];
}>();
</script>

<template>
  <div class="sc-stack sc-stack--large">
    <div class="sc-section-heading">
      <div>
        <p class="sc-eyebrow">REVIEW & ACTIVATION</p>
        <h2>Changes to {{ spacecraft }}</h2>
        <p class="sc-muted">
          Review the exact configuration that will become active for this spacecraft.
        </p>
      </div>
      <span class="sc-tag"
        ><CadenceStatusSymbol
          :status="
            state.review?.status === 'approved' ? 'normal' : changes.length ? 'standby' : 'normal'
          "
        />{{
          state.review?.status === "approved"
            ? "Approved"
            : state.review
              ? "In review"
              : changes.length
                ? "Draft"
                : "Up to date"
        }}</span
      >
    </div>
    <ol v-if="changes.length" class="sc-review-progress" aria-label="Configuration lifecycle">
      <li :class="{ 'is-complete': !unsaved }">
        <span>1</span>{{ unsaved ? "Draft edits" : "Draft saved" }}
      </li>
      <li :class="{ 'is-complete': state.review }"><span>2</span>Review</li>
      <li :class="{ 'is-complete': state.review?.status === 'approved' }">
        <span>3</span>Approval
      </li>
      <li><span>4</span>Activate</li>
    </ol>
    <section v-if="issues.length" class="sc-issues" aria-labelledby="sc-issues-title">
      <header>
        <span class="hero-exclamation-triangle sc-icon" aria-hidden="true" />
        <h3 id="sc-issues-title">
          {{ issues.length }} {{ issues.length === 1 ? "thing" : "things" }} to resolve before
          review
        </h3>
      </header>
      <div v-for="issue in issues" :key="issue.id">
        <p>{{ issue.label }}</p>
        <CadenceButton size="sm" @click="$emit('repair', issue, $event)">{{
          issue.action
        }}</CadenceButton>
      </div>
    </section>
    <section v-if="changes.length" class="sc-surface" aria-labelledby="sc-diff-title">
      <header class="sc-block-heading">
        <h3 id="sc-diff-title">Configuration comparison</h3>
        <span class="sc-count"
          >{{ changes.length }} {{ changes.length === 1 ? "change" : "changes" }}</span
        >
      </header>
      <div class="sc-diff-scroll">
        <table class="sc-diff-table">
          <caption class="sr-only">
            Active configuration compared with
            {{
              unsaved ? "unsaved" : "saved"
            }}
            draft for
            {{
              spacecraft
            }}
          </caption>
          <thead>
            <tr>
              <th scope="col">Setting</th>
              <th scope="col">Active</th>
              <th scope="col">{{ unsaved ? "Unsaved draft" : "Saved draft" }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="change in changes" :key="change.label">
              <th scope="row">{{ change.label }}</th>
              <td>{{ change.before }}</td>
              <td>
                <span class="hero-arrow-right sc-icon-sm" aria-hidden="true" />{{ change.after }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <div
        v-if="state.draft.catalog && state.active?.catalog !== state.draft.catalog"
        class="sc-impact"
      >
        <p class="sc-eyebrow">APPLICATION IMPACT</p>
        <p v-if="state.draft.telemetryEnabled">
          <span class="hero-chart-bar sc-icon" aria-hidden="true" /><strong>Telemetry Decom</strong
          ><span
            >{{ revisions[state.draft.catalog].packets }} packet definitions · input
            {{ state.draft.telemetryInput ? "preserved on VC 0" : "not connected" }}</span
          >
        </p>
        <p v-if="state.draft.commandingEnabled">
          <span class="hero-command-line sc-icon" aria-hidden="true" /><strong>Commanding</strong
          ><span
            >{{ revisions[state.draft.catalog].commands }} command definitions{{
              state.draft.catalog === "3.4" ? " · CAPTURE_IMAGE becomes available" : ""
            }}</span
          >
        </p>
      </div>
      <footer class="sc-review-actions">
        <p>
          {{
            unsaved
              ? "Save your draft before submitting it for review."
              : state.review?.status === "approved"
                ? "Approval applies to the saved configuration shown above."
                : state.review
                  ? "Waiting for a reviewer. The active configuration is unchanged."
                  : issues.length
                    ? "Resolve the setup gaps above to submit this draft."
                    : "Only this spacecraft’s configuration will change."
          }}
        </p>
        <CadenceButton
          v-if="state.review?.status === 'approved'"
          size="sm"
          variant="primary"
          :disabled="!canActivate"
          @click="$emit('activate')"
          >Activate configuration</CadenceButton
        ><CadenceButton
          v-else
          size="sm"
          variant="primary"
          :disabled="!canReview"
          @click="$emit('submit')"
          >{{ state.review ? "Awaiting approval" : "Submit for review" }}</CadenceButton
        >
      </footer>
    </section>
    <div v-else class="sc-complete">
      <CadenceStatusSymbol status="normal" />
      <div>
        <h3>
          {{
            state.active ? "Saved and active configurations match" : "No configuration changes yet"
          }}
        </h3>
        <p class="sc-muted">
          {{
            state.active
              ? "Commanding and telemetry use the active definitions shown on Overview."
              : "Choose a catalog and configure an application to begin."
          }}
        </p>
      </div>
    </div>
    <div v-if="state.review?.status === 'submitted'" class="sc-simulation-control">
      <span class="hero-beaker sc-icon" aria-hidden="true" />
      <div>
        <strong>Storybook simulation</strong>
        <p>Act as the reviewer to explore the next step.</p>
      </div>
      <CadenceButton size="sm" @click="$emit('approve')">Simulate approval</CadenceButton>
    </div>
    <section v-if="state.history.length" class="sc-surface" aria-labelledby="sc-history-title">
      <header class="sc-block-heading">
        <h3 id="sc-history-title">Activation history</h3>
        <span class="sc-muted">This spacecraft</span>
      </header>
      <div
        v-for="(activation, index) in state.history"
        :key="activation.number"
        class="sc-history-row"
      >
        <CadenceStatusSymbol :status="index === 0 ? 'normal' : 'off'" />
        <div>
          <strong>Generation {{ activation.number }} · Kestrel FSW r{{ activation.catalog }}</strong
          ><span>{{ activation.label }}</span>
        </div>
        <span class="sc-muted">{{ index === 0 ? "Active" : "Superseded" }}</span>
      </div>
    </section>
  </div>
</template>
