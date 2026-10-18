<script setup lang="ts">
import type {
  FormField,
  TemplateValues,
  TemplateForm,
  OpsContactRequirementTemplateProps,
  OpsContactRequirementTemplateEmits,
} from "./OpsContactRequirementTemplate.contracts";
import { useOpsHeader } from "@cadence/plugin-sdk/page-header";
import CadenceOpsViewport from "@cadence/ui/CadenceOpsViewport.vue";
import CadenceDetailsFrame from "@cadence/ui/CadenceDetailsFrame.vue";
import CadenceInlineWarning from "@cadence/ui/CadenceInlineWarning.vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import CadenceValidationMessage from "@cadence/ui/CadenceValidationMessage.vue";
import { reactive, watch } from "vue";
import CadencePanel from "@cadence/ui/CadencePanel.vue";

const templateFields = [
  "spacecraft_id",
  "schedule_type",
  "anchor_at",
  "time_utc",
  "interval_minutes",
  "window_offset_minutes",
  "window_duration_minutes",
  "contact_intent",
  "success_measure",
  "minimum_duration_seconds",
  "preferred_duration_seconds",
  "minimum_data_volume_bytes",
  "contact_count",
  "minimum_separation_seconds",
  "priority",
  "approval_mode",
  "maximum_occurrences_per_run",
  "maximum_lookback_hours",
  "rationale",
] as const;

const props = defineProps<OpsContactRequirementTemplateProps>();
useOpsHeader("/missions/:mission_id/ops/requirement-templates", () => ({
  description: props.page.header.copy,
}));

const emit = defineEmits<OpsContactRequirementTemplateEmits>();

const emptyTemplateValues = (): TemplateValues => ({
  spacecraft_id: "",
  schedule_type: "fixed_interval",
  anchor_at: "",
  time_utc: "",
  interval_minutes: "",
  window_offset_minutes: "",
  window_duration_minutes: "",
  contact_intent: "",
  success_measure: "minimum_duration",
  minimum_duration_seconds: "",
  preferred_duration_seconds: "",
  minimum_data_volume_bytes: "",
  contact_count: "",
  minimum_separation_seconds: "",
  priority: "high",
  approval_mode: "manual",
  maximum_occurrences_per_run: "",
  maximum_lookback_hours: "",
  rationale: "",
});

const templateValuesFromForm = (form: TemplateForm | null): TemplateValues => {
  if (!form) return emptyTemplateValues();

  return Object.fromEntries(
    templateFields.map((field) => [field, String(form.fields[field].value ?? "")]),
  ) as TemplateValues;
};

const normalizedTemplate = (values: TemplateValues): TemplateValues =>
  Object.fromEntries(
    templateFields.map((field) => [field, String(values[field] ?? "")]),
  ) as TemplateValues;

const template = reactive<TemplateValues>(templateValuesFromForm(props.template_form));
const pendingValidations: TemplateValues[] = [];
const samePayload = (left: TemplateValues, right: TemplateValues) =>
  JSON.stringify(left) === JSON.stringify(right);

watch(
  () => props.template_form,
  (serverForm) => {
    if (!serverForm) return;

    const serverValues = templateValuesFromForm(serverForm);
    const acknowledgedIndex = pendingValidations.findIndex((sent) =>
      samePayload(sent, serverValues),
    );
    const hasNewerTyping =
      acknowledgedIndex >= 0 && acknowledgedIndex < pendingValidations.length - 1;

    if (acknowledgedIndex >= 0) pendingValidations.splice(0, acknowledgedIndex + 1);
    if (!hasNewerTyping) Object.assign(template, serverValues);
  },
  { deep: true },
);

const validateTemplate = () => {
  const values = normalizedTemplate(template);
  pendingValidations.push(values);
  emit("validate-template", { template: values });
};

const createTemplate = () => {
  emit("create-template", { template: normalizedTemplate(template) });
};

const fieldClass = (field: FormField) => [
  "w-full",
  field.type === "select" ? "select" : field.type === "textarea" ? "textarea" : "input",
  field.errors.length > 0 &&
    (field.type === "select"
      ? "select-error"
      : field.type === "textarea"
        ? "textarea-error"
        : "input-error"),
];
</script>

<template>
  <CadenceOpsViewport :id="page.id">
    <div class="grid gap-5 xl:grid-cols-[minmax(0,1.15fr)_minmax(26rem,0.85fr)]">
      <CadencePanel
        class="min-w-0 border border-base-300 bg-base-200/15"
        header-class="flex items-center justify-between border-b border-base-300 px-4 py-3"
      >
        <template #header>
          <div>
            <p class="hud-label">{{ ledger.eyebrow }}</p>
            <p class="mt-1 text-sm text-base-content/55">{{ ledger.copy }}</p>
          </div>
          <span class="font-mono text-xs text-base-content/45">{{ ledger.count_label }}</span>
        </template>

        <div v-if="ledger.empty" :id="ledger.empty.id" class="px-6 py-16 text-center">
          <span :class="[ledger.empty.icon, 'mx-auto h-8 w-8 text-primary/35']"></span>
          <h2 class="mt-4 text-base font-semibold">{{ ledger.empty.title }}</h2>
          <p class="mx-auto mt-2 max-w-xl text-sm text-base-content/55">{{ ledger.empty.copy }}</p>
        </div>

        <div :id="ledger.list_id">
          <div :id="ledger.stream_empty_id" class="hidden only:block"></div>
          <div
            v-for="requirementTemplate in templates"
            :id="requirementTemplate.__dom_id"
            :key="requirementTemplate.id"
            class="border-b border-base-300 p-4 last:border-b-0"
          >
            <div class="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
              <div class="min-w-0">
                <div class="flex flex-wrap items-center gap-2">
                  <span :class="requirementTemplate.lifecycle.class">
                    {{ requirementTemplate.lifecycle.state }}
                  </span>
                  <span class="font-mono text-[0.6rem] text-base-content/40">
                    {{ requirementTemplate.version_label }}
                  </span>
                </div>
                <h2 class="mt-2 truncate text-sm font-semibold">{{ requirementTemplate.title }}</h2>
                <p class="mt-1 text-xs text-base-content/55">{{ requirementTemplate.schedule }}</p>
                <p class="mt-2 break-all font-mono text-[0.56rem] text-base-content/35">
                  {{ requirementTemplate.content_sha256 }}
                </p>
              </div>
              <div v-if="requirementTemplate.actions" class="flex shrink-0 gap-2">
                <button
                  v-if="requirementTemplate.actions.pause"
                  :id="requirementTemplate.actions.pause.id"
                  type="button"
                  :class="requirementTemplate.actions.pause.class"
                  @click="emit('pause-template', { id: requirementTemplate.id })"
                >
                  {{ requirementTemplate.actions.pause.label }}
                </button>
                <button
                  v-if="requirementTemplate.actions.activate"
                  :id="requirementTemplate.actions.activate.id"
                  type="button"
                  :class="requirementTemplate.actions.activate.class"
                  @click="emit('activate-template', { id: requirementTemplate.id })"
                >
                  {{ requirementTemplate.actions.activate.label }}
                </button>
                <button
                  v-if="requirementTemplate.actions.close"
                  :id="requirementTemplate.actions.close.id"
                  type="button"
                  :class="requirementTemplate.actions.close.class"
                  @click="emit('close-template', { id: requirementTemplate.id })"
                >
                  {{ requirementTemplate.actions.close.label }}
                </button>
              </div>
            </div>
          </div>
        </div>
      </CadencePanel>

      <aside class="min-w-0">
        <CadencePanel
          v-if="template_form"
          :id="template_form.panel_id"
          class="border border-base-300 bg-base-200/15"
          header-class="border-b border-base-300 px-4 py-3"
        >
          <template #header>
            <p class="hud-label">{{ template_form.header.eyebrow }}</p>
            <p class="mt-1 text-xs text-base-content/50">{{ template_form.header.copy }}</p>
          </template>
          <form :id="template_form.id" class="space-y-5 p-4" @submit.prevent="createTemplate">
            <CadenceField
              :control-id="template_form.fields.spacecraft_id.id"
              wrapper-class="fieldset mb-3"
              :label="template_form.fields.spacecraft_id.label"
              label-class="hud-label block mb-1.5"
            >
              <select
                :id="template_form.fields.spacecraft_id.id"
                v-model="template.spacecraft_id"
                :name="template_form.fields.spacecraft_id.name"
                :required="template_form.fields.spacecraft_id.required"
                :class="fieldClass(template_form.fields.spacecraft_id)"
                @change="validateTemplate"
              >
                <option
                  v-for="option in template_form.fields.spacecraft_id.options"
                  :key="option.value"
                  :value="option.value"
                >
                  {{ option.label }}
                </option>
              </select>
              <template #errors>
                <CadenceValidationMessage
                  v-for="error in template_form.fields.spacecraft_id.errors"
                  :key="error"
                  >{{ error }}</CadenceValidationMessage
                >
              </template>
            </CadenceField>

            <div>
              <p class="hud-label">Recurrence</p>
              <div class="mt-3 grid gap-3 sm:grid-cols-2">
                <CadenceField
                  :control-id="template_form.fields.schedule_type.id"
                  wrapper-class="fieldset mb-3"
                  :label="template_form.fields.schedule_type.label"
                  label-class="hud-label block mb-1.5"
                >
                  <select
                    :id="template_form.fields.schedule_type.id"
                    v-model="template.schedule_type"
                    :name="template_form.fields.schedule_type.name"
                    :class="fieldClass(template_form.fields.schedule_type)"
                    @change="validateTemplate"
                  >
                    <option
                      v-for="option in template_form.fields.schedule_type.options"
                      :key="option.value"
                      :value="option.value"
                    >
                      {{ option.label }}
                    </option>
                  </select>
                  <template #errors>
                    <CadenceValidationMessage
                      v-for="error in template_form.fields.schedule_type.errors"
                      :key="error"
                      >{{ error }}</CadenceValidationMessage
                    >
                  </template>
                </CadenceField>

                <CadenceField
                  :control-id="template_form.fields.anchor_at.id"
                  wrapper-class="fieldset mb-3"
                  :label="template_form.fields.anchor_at.label"
                  label-class="hud-label block mb-1.5"
                >
                  <input
                    :id="template_form.fields.anchor_at.id"
                    v-model="template.anchor_at"
                    :name="template_form.fields.anchor_at.name"
                    :type="template_form.fields.anchor_at.type"
                    :step="template_form.fields.anchor_at.step ?? undefined"
                    :required="template_form.fields.anchor_at.required"
                    :class="fieldClass(template_form.fields.anchor_at)"
                    @input="validateTemplate"
                  />
                  <template #errors>
                    <CadenceValidationMessage
                      v-for="error in template_form.fields.anchor_at.errors"
                      :key="error"
                      >{{ error }}</CadenceValidationMessage
                    >
                  </template>
                </CadenceField>

                <CadenceField
                  v-if="template.schedule_type === 'fixed_interval'"
                  :control-id="template_form.fields.interval_minutes.id"
                  wrapper-class="fieldset mb-3"
                  :label="template_form.fields.interval_minutes.label"
                  label-class="hud-label block mb-1.5"
                >
                  <input
                    :id="template_form.fields.interval_minutes.id"
                    v-model="template.interval_minutes"
                    :name="template_form.fields.interval_minutes.name"
                    type="number"
                    :min="template_form.fields.interval_minutes.min ?? undefined"
                    :required="template_form.fields.interval_minutes.required"
                    :class="fieldClass(template_form.fields.interval_minutes)"
                    @input="validateTemplate"
                  />
                  <template #errors>
                    <CadenceValidationMessage
                      v-for="error in template_form.fields.interval_minutes.errors"
                      :key="error"
                      >{{ error }}</CadenceValidationMessage
                    >
                  </template>
                </CadenceField>

                <CadenceField
                  v-if="template.schedule_type === 'daily'"
                  :control-id="template_form.fields.time_utc.id"
                  wrapper-class="fieldset mb-3"
                  :label="template_form.fields.time_utc.label"
                  label-class="hud-label block mb-1.5"
                >
                  <input
                    :id="template_form.fields.time_utc.id"
                    v-model="template.time_utc"
                    :name="template_form.fields.time_utc.name"
                    type="time"
                    :step="template_form.fields.time_utc.step ?? undefined"
                    :required="template_form.fields.time_utc.required"
                    :class="fieldClass(template_form.fields.time_utc)"
                    @input="validateTemplate"
                  />
                  <template #errors>
                    <CadenceValidationMessage
                      v-for="error in template_form.fields.time_utc.errors"
                      :key="error"
                      >{{ error }}</CadenceValidationMessage
                    >
                  </template>
                </CadenceField>

                <CadenceField
                  :control-id="template_form.fields.window_offset_minutes.id"
                  wrapper-class="fieldset mb-3"
                  :label="template_form.fields.window_offset_minutes.label"
                  label-class="hud-label block mb-1.5"
                >
                  <input
                    :id="template_form.fields.window_offset_minutes.id"
                    v-model="template.window_offset_minutes"
                    :name="template_form.fields.window_offset_minutes.name"
                    type="number"
                    :required="template_form.fields.window_offset_minutes.required"
                    :class="fieldClass(template_form.fields.window_offset_minutes)"
                    @input="validateTemplate"
                  />
                  <template #errors>
                    <CadenceValidationMessage
                      v-for="error in template_form.fields.window_offset_minutes.errors"
                      :key="error"
                      >{{ error }}</CadenceValidationMessage
                    >
                  </template>
                </CadenceField>

                <CadenceField
                  :control-id="template_form.fields.window_duration_minutes.id"
                  wrapper-class="fieldset mb-3"
                  :label="template_form.fields.window_duration_minutes.label"
                  label-class="hud-label block mb-1.5"
                >
                  <input
                    :id="template_form.fields.window_duration_minutes.id"
                    v-model="template.window_duration_minutes"
                    :name="template_form.fields.window_duration_minutes.name"
                    type="number"
                    :min="template_form.fields.window_duration_minutes.min ?? undefined"
                    :required="template_form.fields.window_duration_minutes.required"
                    :class="fieldClass(template_form.fields.window_duration_minutes)"
                    @input="validateTemplate"
                  />
                  <template #errors>
                    <CadenceValidationMessage
                      v-for="error in template_form.fields.window_duration_minutes.errors"
                      :key="error"
                      >{{ error }}</CadenceValidationMessage
                    >
                  </template>
                </CadenceField>
              </div>
            </div>

            <div>
              <p class="hud-label">Mission outcome</p>
              <div class="mt-3 grid gap-3 sm:grid-cols-2">
                <CadenceField
                  :control-id="template_form.fields.contact_intent.id"
                  wrapper-class="fieldset mb-3"
                  :label="template_form.fields.contact_intent.label"
                  label-class="hud-label block mb-1.5"
                >
                  <input
                    :id="template_form.fields.contact_intent.id"
                    v-model="template.contact_intent"
                    maxlength="120"
                    :name="template_form.fields.contact_intent.name"
                    type="text"
                    :required="template_form.fields.contact_intent.required"
                    :class="fieldClass(template_form.fields.contact_intent)"
                    @input="validateTemplate"
                  />
                  <template #errors>
                    <CadenceValidationMessage
                      v-for="error in template_form.fields.contact_intent.errors"
                      :key="error"
                      >{{ error }}</CadenceValidationMessage
                    >
                  </template>
                </CadenceField>

                <CadenceField
                  :control-id="template_form.fields.success_measure.id"
                  wrapper-class="fieldset mb-3"
                  :label="template_form.fields.success_measure.label"
                  label-class="hud-label block mb-1.5"
                >
                  <select
                    :id="template_form.fields.success_measure.id"
                    v-model="template.success_measure"
                    :name="template_form.fields.success_measure.name"
                    :class="fieldClass(template_form.fields.success_measure)"
                    @change="validateTemplate"
                  >
                    <option
                      v-for="option in template_form.fields.success_measure.options"
                      :key="option.value"
                      :value="option.value"
                    >
                      {{ option.label }}
                    </option>
                  </select>
                  <template #errors>
                    <CadenceValidationMessage
                      v-for="error in template_form.fields.success_measure.errors"
                      :key="error"
                      >{{ error }}</CadenceValidationMessage
                    >
                  </template>
                </CadenceField>

                <CadenceField
                  v-if="
                    ['minimum_duration', 'minimum_data_volume'].includes(template.success_measure)
                  "
                  :control-id="template_form.fields.minimum_duration_seconds.id"
                  wrapper-class="fieldset mb-3"
                  :label="template_form.fields.minimum_duration_seconds.label"
                  label-class="hud-label block mb-1.5"
                >
                  <input
                    :id="template_form.fields.minimum_duration_seconds.id"
                    v-model="template.minimum_duration_seconds"
                    :name="template_form.fields.minimum_duration_seconds.name"
                    type="number"
                    :min="template_form.fields.minimum_duration_seconds.min ?? undefined"
                    :class="fieldClass(template_form.fields.minimum_duration_seconds)"
                    @input="validateTemplate"
                  />
                  <template #errors>
                    <CadenceValidationMessage
                      v-for="error in template_form.fields.minimum_duration_seconds.errors"
                      :key="error"
                      >{{ error }}</CadenceValidationMessage
                    >
                  </template>
                </CadenceField>

                <CadenceField
                  v-if="template.success_measure === 'minimum_data_volume'"
                  :control-id="template_form.fields.minimum_data_volume_bytes.id"
                  wrapper-class="fieldset mb-3"
                  :label="template_form.fields.minimum_data_volume_bytes.label"
                  label-class="hud-label block mb-1.5"
                >
                  <input
                    :id="template_form.fields.minimum_data_volume_bytes.id"
                    v-model="template.minimum_data_volume_bytes"
                    :name="template_form.fields.minimum_data_volume_bytes.name"
                    type="number"
                    :min="template_form.fields.minimum_data_volume_bytes.min ?? undefined"
                    :class="fieldClass(template_form.fields.minimum_data_volume_bytes)"
                    @input="validateTemplate"
                  />
                  <template #errors>
                    <CadenceValidationMessage
                      v-for="error in template_form.fields.minimum_data_volume_bytes.errors"
                      :key="error"
                      >{{ error }}</CadenceValidationMessage
                    >
                  </template>
                </CadenceField>

                <CadenceField
                  :control-id="template_form.fields.contact_count.id"
                  wrapper-class="fieldset mb-3"
                  :label="template_form.fields.contact_count.label"
                  label-class="hud-label block mb-1.5"
                >
                  <input
                    :id="template_form.fields.contact_count.id"
                    v-model="template.contact_count"
                    :name="template_form.fields.contact_count.name"
                    type="number"
                    :min="template_form.fields.contact_count.min ?? undefined"
                    :required="template_form.fields.contact_count.required"
                    :class="fieldClass(template_form.fields.contact_count)"
                    @input="validateTemplate"
                  />
                  <template #errors>
                    <CadenceValidationMessage
                      v-for="error in template_form.fields.contact_count.errors"
                      :key="error"
                      >{{ error }}</CadenceValidationMessage
                    >
                  </template>
                </CadenceField>

                <CadenceField
                  :control-id="template_form.fields.priority.id"
                  wrapper-class="fieldset mb-3"
                  :label="template_form.fields.priority.label"
                  label-class="hud-label block mb-1.5"
                >
                  <select
                    :id="template_form.fields.priority.id"
                    v-model="template.priority"
                    :name="template_form.fields.priority.name"
                    :class="fieldClass(template_form.fields.priority)"
                    @change="validateTemplate"
                  >
                    <option
                      v-for="option in template_form.fields.priority.options"
                      :key="option.value"
                      :value="option.value"
                    >
                      {{ option.label }}
                    </option>
                  </select>
                  <template #errors>
                    <CadenceValidationMessage
                      v-for="error in template_form.fields.priority.errors"
                      :key="error"
                      >{{ error }}</CadenceValidationMessage
                    >
                  </template>
                </CadenceField>

                <CadenceField
                  :control-id="template_form.fields.approval_mode.id"
                  wrapper-class="fieldset mb-3"
                  :label="template_form.fields.approval_mode.label"
                  label-class="hud-label block mb-1.5"
                >
                  <select
                    :id="template_form.fields.approval_mode.id"
                    v-model="template.approval_mode"
                    :name="template_form.fields.approval_mode.name"
                    :class="fieldClass(template_form.fields.approval_mode)"
                    @change="validateTemplate"
                  >
                    <option
                      v-for="option in template_form.fields.approval_mode.options"
                      :key="option.value"
                      :value="option.value"
                    >
                      {{ option.label }}
                    </option>
                  </select>
                  <template #errors>
                    <CadenceValidationMessage
                      v-for="error in template_form.fields.approval_mode.errors"
                      :key="error"
                      >{{ error }}</CadenceValidationMessage
                    >
                  </template>
                </CadenceField>
              </div>
            </div>

            <CadenceDetailsFrame
              :id="template_form.outcome_details.id"
              class="border border-base-300"
            >
              <summary class="cursor-pointer px-3 py-2 text-xs font-semibold">
                {{ template_form.outcome_details.summary }}
              </summary>
              <div class="grid gap-3 border-t border-base-300 p-3 sm:grid-cols-2">
                <CadenceField
                  :control-id="template_form.fields.preferred_duration_seconds.id"
                  wrapper-class="fieldset mb-3"
                  :label="template_form.fields.preferred_duration_seconds.label"
                  label-class="hud-label block mb-1.5"
                >
                  <input
                    :id="template_form.fields.preferred_duration_seconds.id"
                    v-model="template.preferred_duration_seconds"
                    :name="template_form.fields.preferred_duration_seconds.name"
                    type="number"
                    :min="template_form.fields.preferred_duration_seconds.min ?? undefined"
                    :class="fieldClass(template_form.fields.preferred_duration_seconds)"
                    @input="validateTemplate"
                  />
                  <template #errors>
                    <CadenceValidationMessage
                      v-for="error in template_form.fields.preferred_duration_seconds.errors"
                      :key="error"
                      >{{ error }}</CadenceValidationMessage
                    >
                  </template>
                </CadenceField>
                <CadenceField
                  :control-id="template_form.fields.minimum_separation_seconds.id"
                  wrapper-class="fieldset mb-3"
                  :label="template_form.fields.minimum_separation_seconds.label"
                  label-class="hud-label block mb-1.5"
                >
                  <input
                    :id="template_form.fields.minimum_separation_seconds.id"
                    v-model="template.minimum_separation_seconds"
                    :name="template_form.fields.minimum_separation_seconds.name"
                    type="number"
                    :min="template_form.fields.minimum_separation_seconds.min ?? undefined"
                    :required="template_form.fields.minimum_separation_seconds.required"
                    :class="fieldClass(template_form.fields.minimum_separation_seconds)"
                    @input="validateTemplate"
                  />
                  <template #errors>
                    <CadenceValidationMessage
                      v-for="error in template_form.fields.minimum_separation_seconds.errors"
                      :key="error"
                      >{{ error }}</CadenceValidationMessage
                    >
                  </template>
                </CadenceField>
              </div>
            </CadenceDetailsFrame>

            <CadenceDetailsFrame
              :id="template_form.catchup_details.id"
              class="border border-base-300"
            >
              <summary class="cursor-pointer px-3 py-2 text-xs font-semibold">
                {{ template_form.catchup_details.summary }}
              </summary>
              <div class="grid gap-3 border-t border-base-300 p-3 sm:grid-cols-2">
                <CadenceField
                  :control-id="template_form.fields.maximum_occurrences_per_run.id"
                  wrapper-class="fieldset mb-3"
                  :label="template_form.fields.maximum_occurrences_per_run.label"
                  label-class="hud-label block mb-1.5"
                >
                  <input
                    :id="template_form.fields.maximum_occurrences_per_run.id"
                    v-model="template.maximum_occurrences_per_run"
                    :name="template_form.fields.maximum_occurrences_per_run.name"
                    type="number"
                    :min="template_form.fields.maximum_occurrences_per_run.min ?? undefined"
                    :required="template_form.fields.maximum_occurrences_per_run.required"
                    :class="fieldClass(template_form.fields.maximum_occurrences_per_run)"
                    @input="validateTemplate"
                  />
                  <template #errors>
                    <CadenceValidationMessage
                      v-for="error in template_form.fields.maximum_occurrences_per_run.errors"
                      :key="error"
                      >{{ error }}</CadenceValidationMessage
                    >
                  </template>
                </CadenceField>
                <CadenceField
                  :control-id="template_form.fields.maximum_lookback_hours.id"
                  wrapper-class="fieldset mb-3"
                  :label="template_form.fields.maximum_lookback_hours.label"
                  label-class="hud-label block mb-1.5"
                >
                  <input
                    :id="template_form.fields.maximum_lookback_hours.id"
                    v-model="template.maximum_lookback_hours"
                    :name="template_form.fields.maximum_lookback_hours.name"
                    type="number"
                    :min="template_form.fields.maximum_lookback_hours.min ?? undefined"
                    :required="template_form.fields.maximum_lookback_hours.required"
                    :class="fieldClass(template_form.fields.maximum_lookback_hours)"
                    @input="validateTemplate"
                  />
                  <template #errors>
                    <CadenceValidationMessage
                      v-for="error in template_form.fields.maximum_lookback_hours.errors"
                      :key="error"
                      >{{ error }}</CadenceValidationMessage
                    >
                  </template>
                </CadenceField>
              </div>
            </CadenceDetailsFrame>

            <CadenceField
              :control-id="template_form.fields.rationale.id"
              wrapper-class="fieldset mb-3"
              :label="template_form.fields.rationale.label"
              label-class="hud-label block mb-1.5"
            >
              <textarea
                :id="template_form.fields.rationale.id"
                v-model="template.rationale"
                maxlength="2000"
                :name="template_form.fields.rationale.name"
                :required="template_form.fields.rationale.required"
                :class="fieldClass(template_form.fields.rationale)"
                @input="validateTemplate"
              ></textarea>
              <template #errors>
                <CadenceValidationMessage
                  v-for="error in template_form.fields.rationale.errors"
                  :key="error"
                  >{{ error }}</CadenceValidationMessage
                >
              </template>
            </CadenceField>

            <button
              :id="template_form.submit.id"
              type="submit"
              class="btn btn-primary btn-sm w-full"
            >
              {{ template_form.submit.label }}
            </button>
          </form>
        </CadencePanel>

        <CadenceInlineWarning
          v-if="authorization.admin_required"
          :id="authorization.admin_required.id"
        >
          {{ authorization.admin_required.copy }}
        </CadenceInlineWarning>
      </aside>
    </div>
  </CadenceOpsViewport>
</template>
