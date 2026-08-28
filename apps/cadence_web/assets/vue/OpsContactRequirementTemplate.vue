<script setup lang="ts">
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"
import CadenceField from "./ui/components/CadenceField.vue"
import {reactive, watch} from "vue"
import CadencePanel from "./ui/components/CadencePanel.vue"

type Option = {label: string; value: string}

type FormField = {
  id: string
  name: string
  type: "text" | "number" | "select" | "textarea" | "datetime-local" | "time"
  label: string
  required: boolean
  min: number | null
  step: string | null
  options: Option[]
  value: string
  errors: string[]
}

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
  "rationale"
] as const

type TemplateField = typeof templateFields[number]
type TemplateValues = Record<TemplateField, string>

type TemplateForm = {
  panel_id: string
  id: string
  header: {eyebrow: string; copy: string}
  fields: Record<TemplateField, FormField>
  outcome_details: {id: string; summary: string}
  catchup_details: {id: string; summary: string}
  submit: {id: string; label: string}
}

type LifecycleAction = {id: string; label: string; class: string}

type RequirementTemplate = {
  id: string
  __dom_id: string
  lifecycle: {state: string; class: string}
  version_label: string
  title: string
  schedule: string
  content_sha256: string
  actions?: {
    pause: LifecycleAction | null
    activate: LifecycleAction | null
    close: LifecycleAction | null
  }
}

const props = defineProps<{
  page: {
    id: string
    back: {href: string; icon: string; label: string}
    header: {eyebrow: string; title: string; copy: string}
  }
  ledger: {
    eyebrow: string
    copy: string
    count: number
    count_label: string
    list_id: string
    stream_empty_id: string
    empty: {id: string; icon: string; title: string; copy: string} | null
  }
  authorization: {
    organization_admin: boolean
    admin_required: {id: string; copy: string} | null
  }
  template_form: TemplateForm | null
  templates: RequirementTemplate[]
}>()

const emit = defineEmits<{
  "validate-template": [payload: {template: TemplateValues}]
  "create-template": [payload: {template: TemplateValues}]
  "pause-template": [payload: {id: string}]
  "activate-template": [payload: {id: string}]
  "close-template": [payload: {id: string}]
}>()

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
  rationale: ""
})

const templateValuesFromForm = (form: TemplateForm | null): TemplateValues => {
  if (!form) return emptyTemplateValues()

  return Object.fromEntries(
    templateFields.map((field) => [field, String(form.fields[field].value ?? "")])
  ) as TemplateValues
}

const normalizedTemplate = (values: TemplateValues): TemplateValues =>
  Object.fromEntries(
    templateFields.map((field) => [field, String(values[field] ?? "")])
  ) as TemplateValues

const template = reactive<TemplateValues>(templateValuesFromForm(props.template_form))
const pendingValidations: TemplateValues[] = []
const samePayload = (left: TemplateValues, right: TemplateValues) =>
  JSON.stringify(left) === JSON.stringify(right)

watch(
  () => props.template_form,
  (serverForm) => {
    if (!serverForm) return

    const serverValues = templateValuesFromForm(serverForm)
    const acknowledgedIndex = pendingValidations.findIndex((sent) =>
      samePayload(sent, serverValues)
    )
    const hasNewerTyping =
      acknowledgedIndex >= 0 && acknowledgedIndex < pendingValidations.length - 1

    if (acknowledgedIndex >= 0) pendingValidations.splice(0, acknowledgedIndex + 1)
    if (!hasNewerTyping) Object.assign(template, serverValues)
  },
  {deep: true}
)

const validateTemplate = () => {
  const values = normalizedTemplate(template)
  pendingValidations.push(values)
  emit("validate-template", {template: values})
}

const createTemplate = () => {
  emit("create-template", {template: normalizedTemplate(template)})
}

const fieldClass = (field: FormField) => [
  "w-full",
  field.type === "select" ? "select" : field.type === "textarea" ? "textarea" : "input",
  field.errors.length > 0 &&
    (field.type === "select"
      ? "select-error"
      : field.type === "textarea"
        ? "textarea-error"
        : "input-error")
]
</script>

<template>
  <section :id="page.id" class="h-full overflow-y-auto bg-base-100">
    <CadencePageHeaderFrame variant="ops">
      <div class="mx-auto max-w-[100rem]">
        <a
          :href="page.back.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="inline-flex items-center gap-1 font-mono text-xs text-base-content/55 hover:text-primary"
        >
          <span :class="[page.back.icon, 'h-3.5 w-3.5']"></span>
          {{ page.back.label }}
        </a>
        <div class="mt-4">
          <p class="font-mono text-[0.65rem] uppercase tracking-[0.28em] text-primary/70">
            {{ page.header.eyebrow }}
          </p>
          <h1 class="mt-1 text-2xl font-bold tracking-tight">{{ page.header.title }}</h1>
          <p class="mt-2 max-w-3xl text-sm text-base-content/60">{{ page.header.copy }}</p>
        </div>
      </div>
    </CadencePageHeaderFrame>

    <div class="mx-auto grid max-w-[100rem] gap-5 p-5 xl:grid-cols-[minmax(0,1.15fr)_minmax(26rem,0.85fr)] lg:p-7">
      <CadencePanel class="min-w-0 border border-base-300 bg-base-200/15" header-class="flex items-center justify-between border-b border-base-300 px-4 py-3">
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
                  @click="emit('pause-template', {id: requirementTemplate.id})"
                >
                  {{ requirementTemplate.actions.pause.label }}
                </button>
                <button
                  v-if="requirementTemplate.actions.activate"
                  :id="requirementTemplate.actions.activate.id"
                  type="button"
                  :class="requirementTemplate.actions.activate.class"
                  @click="emit('activate-template', {id: requirementTemplate.id})"
                >
                  {{ requirementTemplate.actions.activate.label }}
                </button>
                <button
                  v-if="requirementTemplate.actions.close"
                  :id="requirementTemplate.actions.close.id"
                  type="button"
                  :class="requirementTemplate.actions.close.class"
                  @click="emit('close-template', {id: requirementTemplate.id})"
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
                >{{ option.label }}</option>
              </select>
              <template #errors>
                <p v-for="error in template_form.fields.spacecraft_id.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>
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
                    >{{ option.label }}</option>
                  </select>
                  <template #errors>
                    <p v-for="error in template_form.fields.schedule_type.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>
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
                    :required="template_form.fields.anchor_at.required"
                    :class="fieldClass(template_form.fields.anchor_at)"
                    @input="validateTemplate"
                  >
                  <template #errors>
                    <p v-for="error in template_form.fields.anchor_at.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>
                  </template>
                </CadenceField>

                <div v-if="template.schedule_type === 'fixed_interval'" class="fieldset mb-3">
                  <label :for="template_form.fields.interval_minutes.id">
                    <span class="hud-label block mb-1.5">{{ template_form.fields.interval_minutes.label }}</span>
                    <input
                      :id="template_form.fields.interval_minutes.id"
                      v-model="template.interval_minutes"
                      :name="template_form.fields.interval_minutes.name"
                      type="number"
                      :min="template_form.fields.interval_minutes.min ?? undefined"
                      :required="template_form.fields.interval_minutes.required"
                      :class="fieldClass(template_form.fields.interval_minutes)"
                      @input="validateTemplate"
                    >
                  </label>
                  <p v-for="error in template_form.fields.interval_minutes.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>
                </div>

                <div v-if="template.schedule_type === 'daily'" class="fieldset mb-3">
                  <label :for="template_form.fields.time_utc.id">
                    <span class="hud-label block mb-1.5">{{ template_form.fields.time_utc.label }}</span>
                    <input
                      :id="template_form.fields.time_utc.id"
                      v-model="template.time_utc"
                      :name="template_form.fields.time_utc.name"
                      type="time"
                      :step="template_form.fields.time_utc.step ?? undefined"
                      :required="template_form.fields.time_utc.required"
                      :class="fieldClass(template_form.fields.time_utc)"
                      @input="validateTemplate"
                    >
                  </label>
                  <p v-for="error in template_form.fields.time_utc.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>
                </div>

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
                  >
                  <template #errors>
                    <p v-for="error in template_form.fields.window_offset_minutes.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>
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
                  >
                  <template #errors>
                    <p v-for="error in template_form.fields.window_duration_minutes.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>
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
                    :name="template_form.fields.contact_intent.name"
                    type="text"
                    :required="template_form.fields.contact_intent.required"
                    :class="fieldClass(template_form.fields.contact_intent)"
                    @input="validateTemplate"
                  >
                  <template #errors>
                    <p v-for="error in template_form.fields.contact_intent.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>
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
                    >{{ option.label }}</option>
                  </select>
                  <template #errors>
                    <p v-for="error in template_form.fields.success_measure.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>
                  </template>
                </CadenceField>

                <div
                  v-if="['minimum_duration', 'minimum_data_volume'].includes(template.success_measure)"
                  class="fieldset mb-3"
                >
                  <label :for="template_form.fields.minimum_duration_seconds.id">
                    <span class="hud-label block mb-1.5">{{ template_form.fields.minimum_duration_seconds.label }}</span>
                    <input
                      :id="template_form.fields.minimum_duration_seconds.id"
                      v-model="template.minimum_duration_seconds"
                      :name="template_form.fields.minimum_duration_seconds.name"
                      type="number"
                      :min="template_form.fields.minimum_duration_seconds.min ?? undefined"
                      :class="fieldClass(template_form.fields.minimum_duration_seconds)"
                      @input="validateTemplate"
                    >
                  </label>
                  <p v-for="error in template_form.fields.minimum_duration_seconds.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>
                </div>

                <div v-if="template.success_measure === 'minimum_data_volume'" class="fieldset mb-3">
                  <label :for="template_form.fields.minimum_data_volume_bytes.id">
                    <span class="hud-label block mb-1.5">{{ template_form.fields.minimum_data_volume_bytes.label }}</span>
                    <input
                      :id="template_form.fields.minimum_data_volume_bytes.id"
                      v-model="template.minimum_data_volume_bytes"
                      :name="template_form.fields.minimum_data_volume_bytes.name"
                      type="number"
                      :min="template_form.fields.minimum_data_volume_bytes.min ?? undefined"
                      :class="fieldClass(template_form.fields.minimum_data_volume_bytes)"
                      @input="validateTemplate"
                    >
                  </label>
                  <p v-for="error in template_form.fields.minimum_data_volume_bytes.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>
                </div>

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
                  >
                  <template #errors>
                    <p v-for="error in template_form.fields.contact_count.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>
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
                    >{{ option.label }}</option>
                  </select>
                  <template #errors>
                    <p v-for="error in template_form.fields.priority.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>
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
                    >{{ option.label }}</option>
                  </select>
                  <template #errors>
                    <p v-for="error in template_form.fields.approval_mode.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>
                  </template>
                </CadenceField>
              </div>
            </div>

            <details :id="template_form.outcome_details.id" class="border border-base-300">
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
                  >
                  <template #errors>
                    <p v-for="error in template_form.fields.preferred_duration_seconds.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>
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
                  >
                  <template #errors>
                    <p v-for="error in template_form.fields.minimum_separation_seconds.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>
                  </template>
                </CadenceField>
              </div>
            </details>

            <details :id="template_form.catchup_details.id" class="border border-base-300">
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
                  >
                  <template #errors>
                    <p v-for="error in template_form.fields.maximum_occurrences_per_run.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>
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
                  >
                  <template #errors>
                    <p v-for="error in template_form.fields.maximum_lookback_hours.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>
                  </template>
                </CadenceField>
              </div>
            </details>

            <CadenceField
              :control-id="template_form.fields.rationale.id"
              wrapper-class="fieldset mb-3"
              :label="template_form.fields.rationale.label"
              label-class="hud-label block mb-1.5"
            >
              <textarea
                :id="template_form.fields.rationale.id"
                v-model="template.rationale"
                :name="template_form.fields.rationale.name"
                :required="template_form.fields.rationale.required"
                :class="fieldClass(template_form.fields.rationale)"
                @input="validateTemplate"
              ></textarea>
              <template #errors>
                <p v-for="error in template_form.fields.rationale.errors" :key="error" class="mt-1.5 text-sm text-error">{{ error }}</p>
              </template>
            </CadenceField>

            <button :id="template_form.submit.id" type="submit" class="btn btn-primary btn-sm w-full">
              {{ template_form.submit.label }}
            </button>
          </form>
        </CadencePanel>

        <p
          v-if="authorization.admin_required"
          :id="authorization.admin_required.id"
          class="border-l-2 border-warning px-3 text-xs text-warning"
        >
          {{ authorization.admin_required.copy }}
        </p>
      </aside>
    </div>
  </section>
</template>
