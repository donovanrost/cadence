<script setup lang="ts">
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import { computed, ref, watch } from "vue";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceDiagnosticsSectionFrame from "@cadence/ui/CadenceDiagnosticsSectionFrame.vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import CadenceStatTile from "@cadence/ui/CadenceStatTile.vue";

import type {
  ConfigurationPresentation,
  LifecycleAction,
  StatusTone,
  PreflightState,
  DiagnosticSeverity,
  ButtonVariant,
} from "./contracts";
const props = defineProps<ConfigurationPresentation & { busy?: boolean }>();

const emit = defineEmits<{
  save_catalog_revision: [
    payload: {
      expected_review: string;
      catalog_revision_id: string;
      handled_apids: number[];
      source_endpoint_id?: string;
      enabled?: boolean;
    },
  ];
  enable: [payload: { "action-id": string; expected_review: string }];
  disable: [payload: { "action-id": string; expected_review: string }];
}>();

const selectedRevisionId = ref(props.revision?.field.value ?? "");

const incomingRevision = ref(props.revision?.field.value ?? "");
const configurationToken = ref(props.review.configuration_token);
const missionToken = ref(props.review.mission_token);
const missionReviewed = ref(false);
const missionChanged = computed(() => missionToken.value !== props.review.mission_token);
const canRequest = computed(
  () => !!props.review.mission_token && !missionChanged.value && missionReviewed.value,
);
watch(
  () => props.review.mission_token,
  () => {
    missionReviewed.value = false;
  },
);
function reviewMission() {
  missionToken.value = props.review.mission_token;
  missionReviewed.value = false;
}
const revisionChanged = computed(
  () =>
    incomingRevision.value !== (props.revision?.field.value ?? "") ||
    configurationToken.value !== props.review.configuration_token,
);
const canSave = computed(
  () =>
    !props.busy &&
    !revisionChanged.value &&
    selectedRevisionId.value !== "" &&
    selectedRevisionId.value !== props.configuration?.catalog_revision_id &&
    props.revision?.field.options.some((option) => option.value === selectedRevisionId.value),
);
watch(
  () => props.context,
  (context, previous) => {
    if (JSON.stringify(context) !== JSON.stringify(previous)) {
      selectedRevisionId.value = props.revision?.field.value ?? "";
      incomingRevision.value = selectedRevisionId.value;
      configurationToken.value = props.review.configuration_token;
      reviewMission();
    }
  },
);
function reloadRevision() {
  selectedRevisionId.value = props.revision?.field.value ?? "";
  incomingRevision.value = selectedRevisionId.value;
  configurationToken.value = props.review.configuration_token;
}
function saveRevision() {
  if (!canSave.value) return;
  if (
    props.configuration &&
    !window.confirm(
      "Use a different catalog revision? Review and save packet inputs for the new revision before requesting mission changes.",
    )
  )
    return;
  emit("save_catalog_revision", {
    expected_review: configurationToken.value,
    catalog_revision_id: selectedRevisionId.value,
    handled_apids: [],
    ...(props.configuration ? { source_endpoint_id: props.configuration.source_endpoint_id } : {}),
  });
}

function enableConfiguration() {
  const config = props.configuration;
  if (
    !config ||
    config.enabled ||
    props.busy ||
    revisionChanged.value ||
    selectedRevisionId.value !== config.catalog_revision_id
  )
    return;
  if (
    !window.confirm(
      "Enable this saved configuration? It will contribute to the next mission changes request.",
    )
  )
    return;
  emit("save_catalog_revision", {
    expected_review: configurationToken.value,
    catalog_revision_id: config.catalog_revision_id,
    source_endpoint_id: config.source_endpoint_id,
    handled_apids: [...config.handled_apids],
    enabled: true,
  });
}

const dispatchLifecycle = (action: LifecycleAction) => {
  if (
    action.disabled ||
    props.busy ||
    selectedRevisionId.value !== (props.revision?.field.value ?? "") ||
    revisionChanged.value
  )
    return;
  if (action.event === "enable" && !canRequest.value) return;
  if (action.confirmation && !window.confirm(action.confirmation.prompt)) return;

  if (action.event === "enable") {
    const token = missionToken.value;
    if (!token) return;
    emit("enable", { "action-id": action.action_id, expected_review: token });
  }
  if (action.event === "disable")
    emit("disable", { "action-id": action.action_id, expected_review: configurationToken.value });
};

const statusDotClasses: Record<StatusTone, string> = {
  ready: "bg-success",
  attention: "bg-warning",
  blocked: "bg-error",
  info: "bg-info",
};

const preflightIconClasses: Record<PreflightState, string> = {
  ready: "border-success/35 bg-success/10 text-success",
  attention: "border-warning/35 bg-warning/10 text-warning",
  blocked: "border-error/35 bg-error/10 text-error",
};

const preflightIcons: Record<PreflightState, string> = {
  ready: "hero-shield-check",
  attention: "hero-exclamation-circle",
  blocked: "hero-shield-exclamation",
};

const statusBadgeClasses: Record<PreflightState, string> = {
  ready: "bg-success/20 text-success",
  attention: "bg-warning/20 text-warning",
  blocked: "bg-error/20 text-error",
};

const checkRailClasses: Record<PreflightState, string> = {
  ready: "bg-success",
  attention: "bg-warning",
  blocked: "bg-error",
};

const checkIcons: Record<PreflightState, string> = {
  ready: "hero-check-circle",
  attention: "hero-exclamation-circle",
  blocked: "hero-x-circle",
};

const checkIconClasses: Record<PreflightState, string> = {
  ready: "text-success",
  attention: "text-warning",
  blocked: "text-error",
};

const diagnosticHeaderIcons: Record<DiagnosticSeverity, string> = {
  error: "hero-exclamation-triangle",
  warning: "hero-exclamation-circle",
  info: "hero-information-circle",
};

const diagnosticHeaderIconClasses: Record<DiagnosticSeverity, string> = {
  error: "border-error/35 bg-error/10 text-error",
  warning: "border-warning/35 bg-warning/10 text-warning",
  info: "border-info/35 bg-info/10 text-info",
};

const diagnosticBadgeClasses: Record<DiagnosticSeverity, string> = {
  error: "bg-error/20 text-error",
  warning: "bg-warning/20 text-warning",
  info: "bg-info/20 text-info",
};

const diagnosticRailClasses: Record<DiagnosticSeverity, string> = {
  error: "bg-error",
  warning: "bg-warning",
  info: "bg-info",
};

const diagnosticItemIcons: Record<DiagnosticSeverity, string> = {
  error: "hero-x-circle",
  warning: "hero-exclamation-circle",
  info: "hero-information-circle",
};

const diagnosticItemIconClasses: Record<DiagnosticSeverity, string> = {
  error: "size-4 shrink-0 text-error",
  warning: "size-4 shrink-0 text-warning",
  info: "size-4 shrink-0 text-info",
};

const buttonClasses: Record<ButtonVariant, string> = {
  primary: "btn-primary",
  secondary: "btn-secondary",
  danger: "btn-error btn-outline",
};
useManagementHeader(
  "/missions/:mission_id/spacecraft/:spacecraft_id/applications/:application_key/:surface_id",
  () => ({
    title: props.page.title,
    description: props.page.subtitle,
  }),
);
</script>

<template>
  <div :id="page.id" class="space-y-6">
    <CadenceCard
      :id="card.id"
      class="card bg-base-200 border border-base-300"
      body-class="card-body p-6"
    >
      <div class="space-y-4">
        <div class="flex items-center justify-between gap-2">
          <div class="flex items-center gap-2">
            <span
              class="rounded-full flex-shrink-0 w-2 h-2"
              :class="statusDotClasses[status.tone]"
            ></span>
            <span class="text-base-content/90">{{ status.label }}</span>
            <span class="text-sm text-base-content/70">— {{ status.description }}</span>
          </div>
          <span v-if="status.saved_label" class="hud-label">{{ status.saved_label }}</span>
        </div>

        <div class="border-t border-base-300/30"></div>

        <div v-if="no_revisions">
          <p class="text-sm text-base-content/70">{{ no_revisions.message }}</p>
          <a
            :href="no_revisions.action.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="btn btn-ghost btn-sm mt-3"
            >{{ no_revisions.action.label }}</a
          >
        </div>

        <template v-else-if="revision">
          <p
            v-if="revisionChanged"
            id="telemetry-decom-stale-revision"
            role="alert"
            class="text-sm text-warning"
          >
            The saved configuration or packet inputs changed. Your selection is retained.
            <button type="button" class="btn btn-sm" @click="reloadRevision">
              Review saved configuration
            </button>
          </p>
          <form
            :id="revision.form_id"
            class="flex max-w-xl flex-wrap items-end gap-3"
            @submit.prevent="saveRevision"
          >
            <CadenceField
              wrapper-class="fieldset mb-3"
              :label="revision.field.label"
              label-class="hud-label block mb-1.5"
            >
              <select
                :id="revision.field.id"
                v-model="selectedRevisionId"
                :name="revision.field.name"
                class="w-full select"
                :disabled="busy"
              >
                <option value="">Select a catalog revision</option>
                <option
                  v-for="option in revision.field.options"
                  :key="option.value"
                  :value="option.value"
                >
                  {{ option.label }}
                </option>
              </select>
            </CadenceField>
            <button
              :id="revision.action.id"
              type="submit"
              class="btn btn-ghost btn-sm mb-3 shrink-0"
              :disabled="!canSave"
            >
              {{ revision.action.label }}
            </button>
          </form>

          <div class="border-t border-base-300/30"></div>

          <section
            v-if="packet_handoff"
            :id="packet_handoff.id"
            class="grid gap-4 md:grid-cols-[minmax(0,1fr)_auto] md:items-center"
          >
            <div>
              <p class="hud-label">{{ packet_handoff.label }}</p>
              <p class="mt-2 text-sm text-base-content/70">
                {{ packet_handoff.selection_count }} of {{ packet_handoff.row_count }}
                {{ packet_handoff.summary_suffix }}
              </p>
              <p class="mt-1 text-xs text-base-content/50">{{ packet_handoff.detail }}</p>
            </div>
            <a
              :id="packet_handoff.action.id"
              :href="packet_handoff.action.href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="btn btn-ghost btn-sm"
              >{{ packet_handoff.action.label }}</a
            >
          </section>

          <div class="border-t border-base-300/30"></div>

          <div v-if="preview" :id="preview.id">
            <p class="hud-label mb-2">{{ preview.label }}</p>
            <p v-if="preview.empty_message" class="text-sm text-base-content/70">
              {{ preview.empty_message }}
            </p>
            <template v-else>
              <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
                <CadenceStatTile v-for="stat in preview.stats" :id="stat.id" :key="stat.id">
                  <template #label>{{ stat.label }}</template>
                  <p class="mt-1 font-mono text-xl text-base-content">{{ stat.value }}</p>
                </CadenceStatTile>
              </div>

              <div v-if="preview.diagnostics" class="mt-3">
                <CadenceDiagnosticsSectionFrame
                  :id="preview.diagnostics.id"
                  :role="preview.diagnostics.role"
                  aria-live="polite"
                  :data-diagnostic-severity="preview.diagnostics.severity"
                  :data-diagnostic-count="preview.diagnostics.count"
                  :data-diagnostic-total="preview.diagnostics.total_count"
                >
                  <template #header>
                    <div
                      class="grid size-9 place-items-center border"
                      :class="diagnosticHeaderIconClasses[preview.diagnostics.severity]"
                    >
                      <span
                        class="size-4"
                        :class="diagnosticHeaderIcons[preview.diagnostics.severity]"
                        aria-hidden="true"
                      ></span>
                    </div>
                    <div class="min-w-0">
                      <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
                        <h2 class="text-sm font-semibold uppercase tracking-[0.14em]">
                          {{ preview.diagnostics.title }}
                        </h2>
                        <span
                          class="font-mono text-[0.65rem] uppercase tracking-[0.16em] text-base-content/45"
                        >
                          {{ preview.diagnostics.count_label }}
                        </span>
                      </div>
                      <p class="mt-1 text-sm text-base-content/65">
                        {{ preview.diagnostics.description }}
                      </p>
                    </div>
                    <span
                      class="inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide"
                      :class="diagnosticBadgeClasses[preview.diagnostics.severity]"
                      >{{ preview.diagnostics.label }}</span
                    >
                  </template>

                  <div :id="preview.diagnostics.items_id" class="divide-y divide-base-300/60">
                    <article
                      v-for="item in preview.diagnostics.items"
                      :id="item.id"
                      :key="item.diagnostic_id"
                      :data-diagnostic-code="item.code"
                      :data-diagnostic-severity="item.severity"
                      class="group grid grid-cols-[0.25rem_minmax(0,1fr)_auto] gap-4 px-4 py-3"
                    >
                      <span
                        class="rounded-full"
                        :class="diagnosticRailClasses[item.severity]"
                      ></span>
                      <div class="min-w-0">
                        <div class="flex flex-wrap items-center gap-2">
                          <span
                            class="font-mono text-[0.62rem] uppercase tracking-[0.13em] text-base-content/45"
                          >
                            {{ item.code }}
                          </span>
                          <h3 class="text-sm font-medium text-base-content">{{ item.title }}</h3>
                        </div>
                        <p class="mt-1 text-xs leading-5 text-base-content/60">{{ item.detail }}</p>
                      </div>
                      <div class="flex items-center gap-3 self-center">
                        <span
                          v-if="item.value"
                          class="max-w-56 truncate font-mono text-xs text-base-content/65"
                          >{{ item.value }}</span
                        >
                        <span
                          :class="[
                            diagnosticItemIcons[item.severity],
                            diagnosticItemIconClasses[item.severity],
                          ]"
                          aria-hidden="true"
                        ></span>
                      </div>
                    </article>
                  </div>
                </CadenceDiagnosticsSectionFrame>
              </div>
            </template>
          </div>
        </template>

        <div class="border-t border-base-300/30"></div>

        <section
          :id="preflight.id"
          :data-preflight-state="preflight.state"
          :data-activation-ready="String(preflight.activation_ready)"
          class="overflow-hidden border border-base-300/80 bg-base-200/30"
        >
          <header
            class="grid gap-4 border-b border-base-300/70 px-4 py-4 sm:grid-cols-[auto_minmax(0,1fr)_auto] sm:items-center"
          >
            <div
              class="grid size-10 place-items-center border"
              :class="preflightIconClasses[preflight.state]"
            >
              <span
                class="size-5"
                :class="preflightIcons[preflight.state]"
                aria-hidden="true"
              ></span>
            </div>
            <div>
              <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
                <h2 class="text-sm font-semibold uppercase tracking-[0.14em]">
                  Activation preflight
                </h2>
                <span
                  class="font-mono text-[0.65rem] uppercase tracking-[0.16em] text-base-content/45"
                >
                  {{ preflight.check_count }} checks · v{{ preflight.application_version }}
                </span>
              </div>
              <p class="mt-1 text-sm text-base-content/65">{{ preflight.summary }}</p>
            </div>
            <span
              data-preflight-summary-status
              class="inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide"
              :class="statusBadgeClasses[preflight.state]"
              >{{ preflight.label }}</span
            >
          </header>

          <div :id="preflight.checks_id" class="divide-y divide-base-300/60">
            <article
              v-for="check in preflight.checks"
              :id="check.id"
              :key="check.check_id"
              :data-check-category="check.category"
              :data-check-state="check.state"
              class="group grid grid-cols-[0.25rem_minmax(0,1fr)_auto] gap-4 px-4 py-3"
            >
              <span class="rounded-full" :class="checkRailClasses[check.state]"></span>
              <div class="min-w-0">
                <div class="flex flex-wrap items-center gap-2">
                  <span
                    class="font-mono text-[0.62rem] uppercase tracking-[0.16em] text-base-content/45"
                  >
                    {{ check.category }}
                  </span>
                  <h3 class="text-sm font-medium text-base-content">{{ check.title }}</h3>
                </div>
                <p class="mt-1 text-xs leading-5 text-base-content/60">{{ check.detail }}</p>
              </div>
              <div class="flex items-center gap-3 self-center">
                <span v-if="check.value" class="font-mono text-xs text-base-content/65">
                  {{ check.value }}
                </span>
                <span
                  class="size-4"
                  :class="[checkIcons[check.state], checkIconClasses[check.state]]"
                  aria-hidden="true"
                ></span>
              </div>
            </article>
          </div>
        </section>

        <div class="border-t border-base-300/30"></div>

        <section
          id="telemetry-decom-mission-review"
          aria-labelledby="telemetry-decom-mission-review-title"
          class="space-y-3"
        >
          <h2 id="telemetry-decom-mission-review-title" class="text-sm font-semibold">
            Mission configuration review
          </h2>
          <p class="text-sm text-base-content/70">
            Requesting mission changes composes enabled Telemetry Decom configurations across this
            mission. Review their saved revisions and packet inputs; activation still requires
            approval.
          </p>
          <p v-if="!review.total_count" class="text-sm text-base-content/70">
            No saved mission configurations.
          </p>
          <ul class="space-y-2">
            <li
              v-for="entry in review.configurations"
              :key="entry.spacecraft_id"
              class="break-all rounded border border-base-300/40 p-3 text-sm"
            >
              <p>
                <strong>{{ entry.spacecraft_name || "Unnamed spacecraft" }}</strong> · Configuration
                v{{ entry.configuration_version }} · {{ entry.enabled ? "Enabled" : "Disabled" }}
              </p>
              <p>Catalog revision: {{ entry.catalog_revision_id }}</p>
              <p>Source endpoint: {{ entry.source_endpoint_name || "Unnamed endpoint" }}</p>
              <p>Saved APIDs: {{ entry.handled_apids.join(", ") || "None" }}</p>
            </li>
          </ul>
          <ul class="space-y-2">
            <li
              v-for="input in review.packet_inputs"
              :key="input.id"
              class="break-all rounded border border-base-300/40 p-3 text-sm"
            >
              <p>
                <strong>{{ input.spacecraft_name || "Unnamed spacecraft" }}</strong> ·
                {{ input.input_id }} v{{ input.configuration_version }} ·
                {{ input.enabled ? "Enabled" : "Disabled" }}
              </p>
              <p>
                {{ input.packet_count }} selected packets. Saved packet inputs override matching
                catalog APID selections.
              </p>
              <a
                :href="`/missions/${context.mission_id}/spacecraft/${input.spacecraft_id}/applications/telemetry_decom/packet_bindings`"
                class="link text-sm"
                data-phx-link="redirect"
                data-phx-link-state="push"
                >Review selected packets</a
              >
            </li>
          </ul>
          <p v-if="review.truncated" role="alert" class="text-sm text-warning">
            Showing 200 of {{ review.total_count }} configurations and inputs. A complete mission
            review is unavailable; mission submission is disabled.
          </p>
          <p
            v-if="missionChanged"
            id="telemetry-decom-stale-mission"
            role="alert"
            class="text-sm text-warning"
          >
            Mission configurations changed. Review the current evidence before submitting.
            <button type="button" class="btn btn-sm" @click="reviewMission">
              Review current mission
            </button>
          </p>
          <label
            v-if="configuration && review.mission_token"
            class="flex items-start gap-2 text-sm"
          >
            <input
              id="telemetry-decom-review-confirmation"
              v-model="missionReviewed"
              type="checkbox"
              class="checkbox checkbox-sm"
              :disabled="busy || missionChanged || revisionChanged"
            />
            <span>I reviewed the mission configurations and packet input versions above.</span>
          </label>
        </section>

        <div v-if="lifecycle_actions.empty_message" class="flex justify-end">
          <p class="text-sm text-base-content/70">{{ lifecycle_actions.empty_message }}</p>
        </div>
        <div v-else class="space-y-3">
          <div
            v-if="pending_activation"
            :id="pending_activation.id"
            role="alert"
            class="border border-info/40 bg-info/10 px-4 py-3 text-sm text-base-content"
          >
            {{ pending_activation.message_before }}
            <span class="font-mono">{{ pending_activation.activation_request_id }}</span>
            {{ pending_activation.message_after }}
          </div>
          <div class="flex flex-wrap justify-end gap-2">
            <button
              v-if="configuration && !configuration.enabled"
              id="telemetry-decom-enable-configuration"
              type="button"
              class="btn btn-ghost btn-sm"
              :disabled="
                busy || revisionChanged || selectedRevisionId !== configuration.catalog_revision_id
              "
              @click="enableConfiguration"
            >
              Enable saved configuration
            </button>
            <button
              v-if="lifecycle_actions.disable"
              :id="lifecycle_actions.disable.id"
              type="button"
              class="btn btn-sm"
              :class="buttonClasses[lifecycle_actions.disable.variant]"
              :data-application-lifecycle-action="lifecycle_actions.disable.action_id"
              :data-lifecycle-effect="lifecycle_actions.disable.effect"
              :data-lifecycle-execution="lifecycle_actions.disable.execution"
              :data-confirmation-required="String(Boolean(lifecycle_actions.disable.confirmation))"
              :data-confirmation-tone="lifecycle_actions.disable.confirmation?.tone"
              :data-confirmation-title="lifecycle_actions.disable.confirmation?.title"
              :data-confirmation-label="lifecycle_actions.disable.confirmation?.confirm_label"
              :data-confirm="lifecycle_actions.disable.confirmation?.prompt"
              :disabled="
                busy ||
                lifecycle_actions.disable.disabled ||
                !configuration ||
                selectedRevisionId !== configuration.catalog_revision_id ||
                revisionChanged
              "
              @click="dispatchLifecycle(lifecycle_actions.disable)"
            >
              {{ lifecycle_actions.disable.label }}
            </button>
            <button
              v-if="lifecycle_actions.enable"
              :id="lifecycle_actions.enable.id"
              type="button"
              class="btn btn-sm"
              :class="buttonClasses[lifecycle_actions.enable.variant]"
              :data-application-lifecycle-action="lifecycle_actions.enable.action_id"
              :data-lifecycle-effect="lifecycle_actions.enable.effect"
              :data-lifecycle-execution="lifecycle_actions.enable.execution"
              :data-confirmation-required="String(Boolean(lifecycle_actions.enable.confirmation))"
              :data-confirmation-tone="lifecycle_actions.enable.confirmation?.tone"
              :data-confirmation-title="lifecycle_actions.enable.confirmation?.title"
              :data-confirmation-label="lifecycle_actions.enable.confirmation?.confirm_label"
              :data-confirm="lifecycle_actions.enable.confirmation?.prompt"
              :disabled="
                busy ||
                lifecycle_actions.enable.disabled ||
                !canRequest ||
                !configuration ||
                selectedRevisionId !== configuration.catalog_revision_id ||
                revisionChanged
              "
              @click="dispatchLifecycle(lifecycle_actions.enable)"
            >
              {{ lifecycle_actions.enable.label }}
            </button>
          </div>
        </div>
      </div>
    </CadenceCard>
  </div>
</template>
