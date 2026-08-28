<script setup lang="ts">
import CadenceField from "./ui/components/CadenceField.vue"
import {onBeforeUnmount, reactive, ref, watch} from "vue"

type Row = {
  label: string
  value: string
}

type Option = {
  label: string
  value: string
}

type SelectField = {
  id: string
  name: string
  type: "select"
  label: string
  options: Option[]
}

type TextField = {
  id: string
  name: string
  type: "text"
  label: string
}

type NumberField = {
  id: string
  name: string
  type: "number"
  label: string
  min: string
  max: string
}

type FilterValues = {
  point_id: string
  spacecraft_id: string
  scope_kind: string
  scope_id: string
  time_mode: string
  time_axis: string
  from: string
  to: string
  replay_run_id: string
  order: string
  limit: string
  selection_view: string
  validity_state: string
  realm: string
  logical_source: string
  data_source_id: string
  source_binding_id: string
  source_dashboard_id: string
  sample_id: string
  selected_time: string
  question: string
  limit_mode: string
}

type FilterForm = {
  id: string
  values: FilterValues
  fields: {
    point_id: SelectField
    spacecraft_id: SelectField
    time_mode: SelectField
    from: TextField
    to: TextField
    order: SelectField
    limit: NumberField
    realm: SelectField
    logical_source: SelectField
    data_source_id: SelectField
    source_binding_id: SelectField
    selection_view: SelectField
    validity_state: SelectField
  }
  submit: {
    id: string
    label: string
    icon: string
  }
}

type Link = {
  id: string
  href: string
  label: string
  icon: string
}

type Page = {
  id: string
  heading: string
  point_label: string
  realm: string | null
  time_mode: string
  source_state: "none" | "matched" | "missing"
  data_source_id: string
  source_binding_id: string
  logical_source: string
  source_realm: string
  selected_sample_state: "none" | "matched" | "missing"
  selected_sample_id: string
  selected_sample_status: {
    id: string
    state: "missing"
    sample_id: string
    icon: string
    heading: string
  } | null
  samples_summary: string
  empty_samples_message: string
}

type Clipboard = {
  button_id: string
  text: string
  class: string
  icon: string
  icon_class: string
  label: string
  copied_message: string
  failed_message: string
}

type Investigation = {
  id: string
  label: string
  path: string
  fingerprint: string
}

type Question = {
  id: string
  dom_id: string
  label: string
  description: string
  icon: string
  active: boolean
}

type QuestionBriefing = {
  id: string
  question: string
  label: string
  text: string
  actions: Link[]
}

type Point = {
  id: string
  requested_point_id: string
  rows: Row[]
  missing: boolean
}

type SelectedSample = {
  id: string
  sample_id: string
  validity_state: string
  rows: Row[]
  clear: {
    id: string
    icon: string
    label: string
  }
  dashboard_link: Link | null
}

type SourceContext = {
  id: string
  state: "none" | "matched" | "missing"
  data_source_id: string
  source_binding_id: string
  logical_source: string
  realm: string
  matched_data_source_id: string
  matched_source_binding_id: string
  rows: Row[]
  actions: Link[]
}

type Diagnostics = {
  id: string
  rows: Row[]
}

type Sample = {
  id: string
  sample_id: string
  selected: boolean
  receipt_time: string
  generation_time: string
  spacecraft_id: string
  engineering_value: string
  raw_value: string
  quality_state: string
  validity_state: string
  source_ref: string
  evidence_id: string
  evidence_display: string
  packet_id: string
  packet_display: string
  packet_definition_id: string
  packet_definition_ref: string
  dashboard_href: string | null
}

type AddToDashboardValues = {
  dashboard_id: string
  widget_type: string
  title: string
}

type Authoring = {
  form: {
    id: string
    note: string
    values: AddToDashboardValues
    fields: {
      dashboard_id: SelectField
      widget_type: SelectField
      title: TextField & {placeholder: string}
    }
    submit: {
      id: string
      label: string
      icon: string
    }
  }
}

const props = defineProps<{
  page: Page
  clipboard: Clipboard
  investigation: Investigation
  navigation: {
    back_to_dashboard: (Link & {class: string}) | null
  }
  questions: Question[]
  question_briefing: QuestionBriefing | null
  filter_form: FilterForm
  point: Point
  selected_sample: SelectedSample | null
  source_context: SourceContext
  context_rows: Row[]
  diagnostics: Diagnostics
  samples: Sample[]
  authoring?: Authoring
}>()

const emit = defineEmits<{
  apply_filters: [payload: {explore: FilterValues}]
  apply_question: [payload: {question: string}]
  add_to_dashboard: [payload: {add_to_dashboard: AddToDashboardValues}]
  clear_selected_sample: [payload: Record<string, never>]
}>()

const stringValue = (value: unknown): string => {
  if (typeof value === "string") return value
  if (value === null || value === undefined) return ""
  return String(value)
}

const filterValuesFromServer = (values: FilterValues): FilterValues => ({
  point_id: stringValue(values.point_id),
  spacecraft_id: stringValue(values.spacecraft_id),
  scope_kind: stringValue(values.scope_kind),
  scope_id: stringValue(values.scope_id),
  time_mode: stringValue(values.time_mode),
  time_axis: stringValue(values.time_axis),
  from: stringValue(values.from),
  to: stringValue(values.to),
  replay_run_id: stringValue(values.replay_run_id),
  order: stringValue(values.order),
  limit: stringValue(values.limit),
  selection_view: stringValue(values.selection_view),
  validity_state: stringValue(values.validity_state),
  realm: stringValue(values.realm),
  logical_source: stringValue(values.logical_source),
  data_source_id: stringValue(values.data_source_id),
  source_binding_id: stringValue(values.source_binding_id),
  source_dashboard_id: stringValue(values.source_dashboard_id),
  sample_id: stringValue(values.sample_id),
  selected_time: stringValue(values.selected_time),
  question: stringValue(values.question),
  limit_mode: stringValue(values.limit_mode)
})

const addValuesFromServer = (values?: AddToDashboardValues): AddToDashboardValues => ({
  dashboard_id: stringValue(values?.dashboard_id),
  widget_type: stringValue(values?.widget_type),
  title: stringValue(values?.title)
})

const sameFilterValues = (left: FilterValues, right: FilterValues) =>
  Object.keys(left).every(key => left[key as keyof FilterValues] === right[key as keyof FilterValues])

const sameAddValues = (left: AddToDashboardValues, right: AddToDashboardValues) =>
  left.dashboard_id === right.dashboard_id &&
  left.widget_type === right.widget_type &&
  left.title === right.title

const filterValues = reactive<FilterValues>(filterValuesFromServer(props.filter_form.values))
let lastFilterServerValues = filterValuesFromServer(props.filter_form.values)
let pendingFilterSubmission: FilterValues | undefined

const addToDashboardValues = reactive<AddToDashboardValues>(
  addValuesFromServer(props.authoring?.form.values)
)
let lastAddServerValues = props.authoring
  ? addValuesFromServer(props.authoring.form.values)
  : undefined
let pendingAddSubmission: AddToDashboardValues | undefined

watch(
  () => props.filter_form.values,
  serverValues => {
    const normalizedServerValues = filterValuesFromServer(serverValues)
    const currentValues = filterValuesFromServer(filterValues)
    const currentMatchesPreviousServer = sameFilterValues(currentValues, lastFilterServerValues)
    const currentMatchesSubmission =
      pendingFilterSubmission !== undefined &&
      sameFilterValues(currentValues, pendingFilterSubmission)

    lastFilterServerValues = normalizedServerValues
    pendingFilterSubmission = undefined

    if (currentMatchesPreviousServer || currentMatchesSubmission) {
      Object.assign(filterValues, normalizedServerValues)
    }
  },
  {deep: true}
)

watch(
  () => props.authoring?.form.values,
  serverValues => {
    if (serverValues === undefined) {
      lastAddServerValues = undefined
      pendingAddSubmission = undefined
      Object.assign(addToDashboardValues, addValuesFromServer())
      return
    }

    const normalizedServerValues = addValuesFromServer(serverValues)
    const currentValues = addValuesFromServer(addToDashboardValues)
    const currentMatchesPreviousServer =
      lastAddServerValues === undefined || sameAddValues(currentValues, lastAddServerValues)
    const currentMatchesSubmission =
      pendingAddSubmission !== undefined && sameAddValues(currentValues, pendingAddSubmission)

    lastAddServerValues = normalizedServerValues
    pendingAddSubmission = undefined

    if (currentMatchesPreviousServer || currentMatchesSubmission) {
      Object.assign(addToDashboardValues, normalizedServerValues)
    }
  },
  {deep: true}
)

const applyFilters = () => {
  const values = filterValuesFromServer(filterValues)
  pendingFilterSubmission = values
  emit("apply_filters", {explore: values})
}

const applyQuestion = (question: Question) => {
  emit("apply_question", {question: stringValue(question.id)})
}

const addToDashboard = () => {
  const values = addValuesFromServer(addToDashboardValues)
  pendingAddSubmission = values
  emit("add_to_dashboard", {add_to_dashboard: values})
}

const clearSelectedSample = () => emit("clear_selected_sample", {})

const clipboardFeedback = ref<"" | "copied" | "failed">("")
let clearClipboardTimer: ReturnType<typeof setTimeout> | undefined

const markClipboardFeedback = (state: "copied" | "failed") => {
  clipboardFeedback.value = state

  if (clearClipboardTimer !== undefined) clearTimeout(clearClipboardTimer)

  clearClipboardTimer = setTimeout(() => {
    clipboardFeedback.value = ""
    clearClipboardTimer = undefined
  }, 1500)
}

const fallbackCopy = (text: string) => {
  const textarea = document.createElement("textarea")
  textarea.value = text
  textarea.setAttribute("readonly", "readonly")
  textarea.style.position = "fixed"
  textarea.style.opacity = "0"
  document.body.appendChild(textarea)

  try {
    textarea.select()
    return document.execCommand("copy")
  } finally {
    textarea.remove()
  }
}

const copyInvestigationLink = async () => {
  let absoluteText: string

  try {
    absoluteText = new URL(props.clipboard.text, window.location.origin).toString()
  } catch (_error) {
    markClipboardFeedback("failed")
    return
  }

  try {
    await navigator.clipboard.writeText(absoluteText)
    markClipboardFeedback("copied")
  } catch (_error) {
    try {
      markClipboardFeedback(fallbackCopy(absoluteText) === false ? "failed" : "copied")
    } catch (_fallbackError) {
      markClipboardFeedback("failed")
    }
  }
}

onBeforeUnmount(() => {
  if (clearClipboardTimer !== undefined) clearTimeout(clearClipboardTimer)
})
</script>

<template>
  <div
    :id="page.id"
    class="flex flex-1 min-h-0"
    :data-explore-source-state="page.source_state"
    :data-explore-data-source="page.data_source_id"
    :data-explore-source-binding="page.source_binding_id"
    :data-explore-logical-source="page.logical_source"
    :data-explore-realm="page.source_realm"
    :data-explore-selected-sample-state="page.selected_sample_state"
    :data-explore-selected-sample-id="page.selected_sample_id"
  >
    <div class="flex-1 min-w-0 overflow-y-auto">
      <div class="mx-auto max-w-7xl px-6 py-8">
        <div class="flex flex-col gap-3 border-b border-base-300/60 pb-5 md:flex-row md:items-end md:justify-between">
          <div>
            <div class="flex flex-wrap items-center gap-2">
              <h1 class="text-lg font-semibold text-base-content">{{ page.heading }}</h1>
              <span v-if="page.realm" class="badge badge-xs badge-outline">{{ page.realm }}</span>
              <span v-if="page.time_mode" class="badge badge-xs">{{ page.time_mode }}</span>
            </div>
            <p class="mt-1 font-mono text-xs text-base-content/60">{{ page.point_label }}</p>
          </div>
          <div class="flex flex-wrap gap-2">
            <button
              :id="clipboard.button_id"
              type="button"
              :class="clipboard.class"
              data-clipboard-button
              :data-clipboard-text="clipboard.text"
              :data-clipboard-copied="clipboardFeedback === 'copied' ? 'true' : undefined"
              :data-clipboard-failed="clipboardFeedback === 'failed' ? 'true' : undefined"
              @click="copyInvestigationLink"
            >
              <span :class="[clipboard.icon, clipboard.icon_class]" aria-hidden="true"></span>
              {{ clipboard.label }}
            </button>
            <span class="sr-only" role="status" aria-live="polite" aria-atomic="true">
              <template v-if="clipboardFeedback === 'copied'">{{ clipboard.copied_message }}</template>
              <template v-else-if="clipboardFeedback === 'failed'">{{ clipboard.failed_message }}</template>
            </span>
            <a
              v-if="navigation.back_to_dashboard"
              :id="navigation.back_to_dashboard.id"
              :href="navigation.back_to_dashboard.href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              :class="navigation.back_to_dashboard.class"
            >
              <span :class="[navigation.back_to_dashboard.icon, 'h-4 w-4']" aria-hidden="true"></span>
              {{ navigation.back_to_dashboard.label }}
            </a>
          </div>
        </div>

        <section id="telemetry-explore-questions" class="mt-5 border border-primary/20 bg-primary/[0.035] p-4">
          <div class="flex flex-col gap-2 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p class="hud-label">Start with an operational question</p>
              <p class="mt-1 text-sm text-base-content/60">
                Presets establish typed time, revision, source, and follow-on context. Refine the exact point below.
              </p>
            </div>
            <span v-if="question_briefing" class="badge badge-sm badge-primary badge-outline">
              {{ question_briefing.label }}
            </span>
          </div>
          <div class="mt-3 grid gap-2 sm:grid-cols-2 xl:grid-cols-4">
            <button
              v-for="question in questions"
              :id="question.dom_id"
              :key="question.id"
              type="button"
              :class="[
                'group border p-3 text-left transition-colors hover:border-primary/50 hover:bg-primary/5',
                question.active ? 'border-primary/60 bg-primary/10' : 'border-base-300 bg-base-100/45'
              ]"
              @click="applyQuestion(question)"
            >
              <span class="flex items-center gap-2 text-sm font-semibold">
                <span :class="[question.icon, 'h-4 w-4 text-primary']" aria-hidden="true"></span>
                {{ question.label }}
              </span>
              <span class="mt-1 block text-xs leading-relaxed text-base-content/55">
                {{ question.description }}
              </span>
            </button>
          </div>
          <div
            v-if="question_briefing"
            :id="question_briefing.id"
            class="mt-3 flex flex-col gap-3 border-t border-primary/15 pt-3 text-xs lg:flex-row lg:items-center"
            :data-explore-question="question_briefing.question"
          >
            <p class="min-w-0 flex-1 text-base-content/65">{{ question_briefing.text }}</p>
            <div class="flex flex-wrap gap-2">
              <a
                v-for="action in question_briefing.actions"
                :id="action.id"
                :key="action.id"
                :href="action.href"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="btn btn-xs btn-outline"
              >
                <span :class="[action.icon, 'h-3.5 w-3.5']" aria-hidden="true"></span>
                {{ action.label }}
              </a>
            </div>
          </div>
        </section>

        <form
          :id="filter_form.id"
          class="mt-5 border border-base-300/70 bg-base-100/40 p-4"
          @submit.prevent="applyFilters"
        >
          <input v-model="filterValues.source_dashboard_id" type="hidden" name="explore[source_dashboard_id]">
          <input v-model="filterValues.sample_id" type="hidden" name="explore[sample_id]">
          <input v-model="filterValues.selected_time" type="hidden" name="explore[selected_time]">
          <input v-model="filterValues.question" type="hidden" name="explore[question]">
          <input v-model="filterValues.scope_kind" type="hidden" name="explore[scope_kind]">
          <input v-model="filterValues.scope_id" type="hidden" name="explore[scope_id]">
          <input v-model="filterValues.time_axis" type="hidden" name="explore[time_axis]">
          <input v-model="filterValues.replay_run_id" type="hidden" name="explore[replay_run_id]">
          <input v-model="filterValues.limit_mode" type="hidden" name="explore[limit_mode]">

          <div class="grid gap-3 lg:grid-cols-[minmax(12rem,1.25fr)_minmax(10rem,1fr)_9rem_10rem_10rem_8rem_auto] lg:items-end">
            <CadenceField
              :control-id="filter_form.fields.point_id.id"
              wrapper-class="fieldset"
              :label="filter_form.fields.point_id.label"
              label-class="hud-label block mb-1.5"
            >
              <select
                :id="filter_form.fields.point_id.id"
                v-model="filterValues.point_id"
                :name="filter_form.fields.point_id.name"
                class="w-full select"
              >
                <option v-for="option in filter_form.fields.point_id.options" :key="option.value" :value="option.value">{{ option.label }}</option>
              </select>
            </CadenceField>
            <CadenceField
              :control-id="filter_form.fields.spacecraft_id.id"
              wrapper-class="fieldset"
              :label="filter_form.fields.spacecraft_id.label"
              label-class="hud-label block mb-1.5"
            >
              <select
                :id="filter_form.fields.spacecraft_id.id"
                v-model="filterValues.spacecraft_id"
                :name="filter_form.fields.spacecraft_id.name"
                class="w-full select"
              >
                <option v-for="option in filter_form.fields.spacecraft_id.options" :key="option.value" :value="option.value">{{ option.label }}</option>
              </select>
            </CadenceField>
            <CadenceField
              :control-id="filter_form.fields.time_mode.id"
              wrapper-class="fieldset"
              :label="filter_form.fields.time_mode.label"
              label-class="hud-label block mb-1.5"
            >
              <select
                :id="filter_form.fields.time_mode.id"
                v-model="filterValues.time_mode"
                :name="filter_form.fields.time_mode.name"
                class="w-full select"
              >
                <option v-for="option in filter_form.fields.time_mode.options" :key="option.value" :value="option.value">{{ option.label }}</option>
              </select>
            </CadenceField>
            <CadenceField
              :control-id="filter_form.fields.from.id"
              wrapper-class="fieldset"
              :label="filter_form.fields.from.label"
              label-class="hud-label block mb-1.5"
            >
              <input
                :id="filter_form.fields.from.id"
                v-model="filterValues.from"
                :name="filter_form.fields.from.name"
                :type="filter_form.fields.from.type"
                class="w-full input"
              >
            </CadenceField>
            <CadenceField
              :control-id="filter_form.fields.to.id"
              wrapper-class="fieldset"
              :label="filter_form.fields.to.label"
              label-class="hud-label block mb-1.5"
            >
              <input
                :id="filter_form.fields.to.id"
                v-model="filterValues.to"
                :name="filter_form.fields.to.name"
                :type="filter_form.fields.to.type"
                class="w-full input"
              >
            </CadenceField>
            <CadenceField
              :control-id="filter_form.fields.order.id"
              wrapper-class="fieldset"
              :label="filter_form.fields.order.label"
              label-class="hud-label block mb-1.5"
            >
              <select
                :id="filter_form.fields.order.id"
                v-model="filterValues.order"
                :name="filter_form.fields.order.name"
                class="w-full select"
              >
                <option v-for="option in filter_form.fields.order.options" :key="option.value" :value="option.value">{{ option.label }}</option>
              </select>
            </CadenceField>
            <div class="grid grid-cols-[minmax(0,1fr)_auto] gap-2">
              <CadenceField
                :control-id="filter_form.fields.limit.id"
                wrapper-class="fieldset"
                :label="filter_form.fields.limit.label"
                label-class="hud-label block mb-1.5"
              >
                <input
                  :id="filter_form.fields.limit.id"
                  v-model="filterValues.limit"
                  :name="filter_form.fields.limit.name"
                  :type="filter_form.fields.limit.type"
                  :min="filter_form.fields.limit.min"
                  :max="filter_form.fields.limit.max"
                  class="w-full input"
                >
              </CadenceField>
              <button :id="filter_form.submit.id" type="submit" class="btn btn-primary btn-sm">
                <span :class="[filter_form.submit.icon, 'h-4 w-4']" aria-hidden="true"></span>
                {{ filter_form.submit.label }}
              </button>
            </div>
          </div>
          <div class="mt-3 grid gap-3 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
            <CadenceField
              :control-id="filter_form.fields.realm.id"
              wrapper-class="fieldset"
              :label="filter_form.fields.realm.label"
              label-class="hud-label block mb-1.5"
            >
              <select
                :id="filter_form.fields.realm.id"
                v-model="filterValues.realm"
                :name="filter_form.fields.realm.name"
                class="w-full select"
              >
                <option v-for="option in filter_form.fields.realm.options" :key="option.value" :value="option.value">{{ option.label }}</option>
              </select>
            </CadenceField>
            <CadenceField
              :control-id="filter_form.fields.logical_source.id"
              wrapper-class="fieldset"
              :label="filter_form.fields.logical_source.label"
              label-class="hud-label block mb-1.5"
            >
              <select
                :id="filter_form.fields.logical_source.id"
                v-model="filterValues.logical_source"
                :name="filter_form.fields.logical_source.name"
                class="w-full select"
              >
                <option v-for="option in filter_form.fields.logical_source.options" :key="option.value" :value="option.value">{{ option.label }}</option>
              </select>
            </CadenceField>
            <CadenceField
              :control-id="filter_form.fields.data_source_id.id"
              wrapper-class="fieldset"
              :label="filter_form.fields.data_source_id.label"
              label-class="hud-label block mb-1.5"
            >
              <select
                :id="filter_form.fields.data_source_id.id"
                v-model="filterValues.data_source_id"
                :name="filter_form.fields.data_source_id.name"
                class="w-full select"
              >
                <option v-for="option in filter_form.fields.data_source_id.options" :key="option.value" :value="option.value">{{ option.label }}</option>
              </select>
            </CadenceField>
            <CadenceField
              :control-id="filter_form.fields.source_binding_id.id"
              wrapper-class="fieldset"
              :label="filter_form.fields.source_binding_id.label"
              label-class="hud-label block mb-1.5"
            >
              <select
                :id="filter_form.fields.source_binding_id.id"
                v-model="filterValues.source_binding_id"
                :name="filter_form.fields.source_binding_id.name"
                class="w-full select"
              >
                <option v-for="option in filter_form.fields.source_binding_id.options" :key="option.value" :value="option.value">{{ option.label }}</option>
              </select>
            </CadenceField>
            <CadenceField
              :control-id="filter_form.fields.selection_view.id"
              wrapper-class="fieldset"
              :label="filter_form.fields.selection_view.label"
              label-class="hud-label block mb-1.5"
            >
              <select
                :id="filter_form.fields.selection_view.id"
                v-model="filterValues.selection_view"
                :name="filter_form.fields.selection_view.name"
                class="w-full select"
              >
                <option v-for="option in filter_form.fields.selection_view.options" :key="option.value" :value="option.value">{{ option.label }}</option>
              </select>
            </CadenceField>
            <CadenceField
              :control-id="filter_form.fields.validity_state.id"
              wrapper-class="fieldset"
              :label="filter_form.fields.validity_state.label"
              label-class="hud-label block mb-1.5"
            >
              <select
                :id="filter_form.fields.validity_state.id"
                v-model="filterValues.validity_state"
                :name="filter_form.fields.validity_state.name"
                class="w-full select"
              >
                <option v-for="option in filter_form.fields.validity_state.options" :key="option.value" :value="option.value">{{ option.label }}</option>
              </select>
            </CadenceField>
          </div>
        </form>

        <div
          :id="investigation.id"
          class="mt-3 flex flex-wrap items-center gap-2 text-xs text-base-content/60"
          :data-investigation-path="investigation.path"
          :data-investigation-fingerprint="investigation.fingerprint"
        >
          <span class="hud-label">{{ investigation.label }}</span>
          <span class="font-mono text-base-content/70">{{ investigation.fingerprint }}</span>
          <span class="font-mono break-all">{{ investigation.path }}</span>
        </div>

        <div
          v-if="page.selected_sample_status"
          :id="page.selected_sample_status.id"
          class="mt-3 flex items-start gap-3 border border-warning/30 bg-warning/10 px-4 py-3 text-sm"
          :data-explore-selected-sample-state="page.selected_sample_status.state"
          :data-explore-selected-sample-id="page.selected_sample_status.sample_id"
        >
          <span :class="[page.selected_sample_status.icon, 'mt-0.5 h-4 w-4 shrink-0']" aria-hidden="true"></span>
          <div class="min-w-0">
            <p class="font-semibold">{{ page.selected_sample_status.heading }}</p>
            <p class="mt-1 break-all font-mono text-xs text-base-content/60">
              {{ page.selected_sample_status.sample_id }}
            </p>
          </div>
        </div>

        <div class="mt-6 grid gap-4 xl:grid-cols-[22rem_minmax(0,1fr)]">
          <aside class="space-y-4">
            <section :id="point.id" class="border border-base-300/70 bg-base-100/40 p-4">
              <h2 class="hud-label">Point</h2>
              <dl class="mt-3 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-2 text-xs">
                <template v-for="row in point.rows" :key="row.label">
                  <dt class="text-base-content/60">{{ row.label }}</dt>
                  <dd
                    :class="row.label === 'Description' ? 'text-base-content break-words' : 'font-mono text-base-content break-all'"
                    :data-explore-point-field="row.label"
                  >{{ row.value }}</dd>
                </template>
              </dl>
              <p v-if="point.missing" class="mt-3 text-sm text-warning">
                Point is not present in the active operator point catalog.
              </p>

              <form
                v-if="authoring"
                :id="authoring.form.id"
                class="mt-4 space-y-3 border-t border-base-300/70 pt-4"
                @submit.prevent="addToDashboard"
              >
                <div class="flex items-center justify-between gap-2">
                  <h3 class="hud-label">Stage in dashboard</h3>
                  <span class="font-mono text-[0.65rem] text-base-content/45">{{ authoring.form.note }}</span>
                </div>
                <CadenceField
                  :control-id="authoring.form.fields.dashboard_id.id"
                  wrapper-class="fieldset"
                  :label="authoring.form.fields.dashboard_id.label"
                  label-class="hud-label block mb-1.5"
                >
                  <select
                    :id="authoring.form.fields.dashboard_id.id"
                    v-model="addToDashboardValues.dashboard_id"
                    :name="authoring.form.fields.dashboard_id.name"
                    class="w-full select"
                  >
                    <option v-for="option in authoring.form.fields.dashboard_id.options" :key="option.value" :value="option.value">{{ option.label }}</option>
                  </select>
                </CadenceField>
                <CadenceField
                  :control-id="authoring.form.fields.widget_type.id"
                  wrapper-class="fieldset"
                  :label="authoring.form.fields.widget_type.label"
                  label-class="hud-label block mb-1.5"
                >
                  <select
                    :id="authoring.form.fields.widget_type.id"
                    v-model="addToDashboardValues.widget_type"
                    :name="authoring.form.fields.widget_type.name"
                    class="w-full select"
                  >
                    <option v-for="option in authoring.form.fields.widget_type.options" :key="option.value" :value="option.value">{{ option.label }}</option>
                  </select>
                </CadenceField>
                <CadenceField
                  :control-id="authoring.form.fields.title.id"
                  wrapper-class="fieldset"
                  :label="authoring.form.fields.title.label"
                  label-class="hud-label block mb-1.5"
                >
                  <input
                    :id="authoring.form.fields.title.id"
                    v-model="addToDashboardValues.title"
                    :name="authoring.form.fields.title.name"
                    :type="authoring.form.fields.title.type"
                    :placeholder="authoring.form.fields.title.placeholder"
                    class="w-full input"
                  >
                </CadenceField>
                <button :id="authoring.form.submit.id" type="submit" class="btn btn-primary btn-sm w-full">
                  <span :class="[authoring.form.submit.icon, 'h-4 w-4']" aria-hidden="true"></span>
                  {{ authoring.form.submit.label }}
                </button>
              </form>
            </section>

            <section
              v-if="selected_sample"
              :id="selected_sample.id"
              class="border border-primary/30 bg-base-100/50 p-4"
              :data-explore-selected-sample-card="selected_sample.sample_id"
            >
              <div class="flex items-center justify-between gap-3">
                <h2 class="hud-label">Selected Sample</h2>
                <div class="flex items-center gap-2">
                  <span class="badge badge-xs badge-outline">{{ selected_sample.validity_state }}</span>
                  <button
                    :id="selected_sample.clear.id"
                    type="button"
                    class="btn btn-ghost btn-xs"
                    :aria-label="selected_sample.clear.label"
                    @click="clearSelectedSample"
                  >
                    <span :class="[selected_sample.clear.icon, 'h-3.5 w-3.5']" aria-hidden="true"></span>
                  </button>
                </div>
              </div>
              <dl class="mt-3 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-2 text-xs">
                <template v-for="row in selected_sample.rows" :key="row.label">
                  <dt class="text-base-content/60">{{ row.label }}</dt>
                  <dd class="font-mono text-base-content break-all" :data-explore-selected-provenance="row.label">{{ row.value }}</dd>
                </template>
              </dl>
              <div v-if="selected_sample.dashboard_link" class="mt-3">
                <a
                  :id="selected_sample.dashboard_link.id"
                  :href="selected_sample.dashboard_link.href"
                  data-phx-link="redirect"
                  data-phx-link-state="push"
                  class="btn btn-xs btn-outline w-full justify-start"
                >
                  <span :class="[selected_sample.dashboard_link.icon, 'h-3.5 w-3.5']" aria-hidden="true"></span>
                  {{ selected_sample.dashboard_link.label }}
                </a>
              </div>
            </section>

            <section
              :id="source_context.id"
              :class="[
                'border bg-base-100/40 p-4',
                source_context.state === 'matched' && 'border-primary/30',
                source_context.state === 'missing' && 'border-warning/30',
                source_context.state === 'none' && 'border-base-300/70'
              ]"
              :data-explore-source-state="source_context.state"
              :data-explore-data-source="source_context.data_source_id"
              :data-explore-source-binding="source_context.source_binding_id"
              :data-explore-logical-source="source_context.logical_source"
              :data-explore-realm="source_context.realm"
              :data-explore-matched-data-source="source_context.matched_data_source_id"
              :data-explore-matched-source-binding="source_context.matched_source_binding_id"
            >
              <h2 class="hud-label">Source Context</h2>
              <dl class="mt-3 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-2 text-xs">
                <template v-for="row in source_context.rows" :key="row.label">
                  <dt class="text-base-content/60">{{ row.label }}</dt>
                  <dd class="font-mono text-base-content break-all" :data-explore-source="row.label">{{ row.value }}</dd>
                </template>
              </dl>
              <div class="mt-3 grid gap-2">
                <a
                  v-for="action in source_context.actions"
                  :id="action.id"
                  :key="action.id"
                  :href="action.href"
                  data-phx-link="redirect"
                  data-phx-link-state="push"
                  class="btn btn-xs btn-outline justify-start"
                >
                  <span :class="[action.icon, 'h-3.5 w-3.5']" aria-hidden="true"></span>
                  {{ action.label }}
                </a>
              </div>
            </section>

            <section id="telemetry-explore-context-card" class="border border-base-300/70 bg-base-100/40 p-4">
              <h2 class="hud-label">Context</h2>
              <dl class="mt-3 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-2 text-xs">
                <template v-for="row in context_rows" :key="row.label">
                  <dt class="text-base-content/60">{{ row.label }}</dt>
                  <dd class="font-mono text-base-content break-all" :data-explore-context="row.label">{{ row.value }}</dd>
                </template>
              </dl>
            </section>

            <section :id="diagnostics.id" class="border border-base-300/70 bg-base-100/40 p-4">
              <h2 class="hud-label">Read Diagnostics</h2>
              <dl class="mt-3 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-2 text-xs">
                <template v-for="row in diagnostics.rows" :key="row.label">
                  <dt class="text-base-content/60">{{ row.label }}</dt>
                  <dd class="font-mono text-base-content break-all" :data-explore-diagnostics="row.label">{{ row.value }}</dd>
                </template>
              </dl>
            </section>
          </aside>

          <section class="min-w-0 border border-base-300/70 bg-base-100/40">
            <header class="flex items-center justify-between gap-3 border-b border-base-300/70 px-4 py-3">
              <div>
                <h2 class="hud-label">Samples</h2>
                <p class="mt-1 text-xs text-base-content/60">{{ page.samples_summary }}</p>
              </div>
              <span
                v-if="page.selected_sample_id"
                class="badge badge-xs badge-outline font-mono"
                :data-explore-selected-sample="page.selected_sample_id"
                :data-explore-selected-sample-state="page.selected_sample_state"
              >{{ page.selected_sample_id }}</span>
            </header>

            <div class="overflow-x-auto">
              <table id="telemetry-explore-samples" class="table table-xs">
                <thead>
                  <tr>
                    <th>Receipt</th>
                    <th>Generation</th>
                    <th>Spacecraft</th>
                    <th>Engineering</th>
                    <th>Raw</th>
                    <th>Quality</th>
                    <th>Validity</th>
                    <th>Source</th>
                    <th>Evidence</th>
                    <th>Packet</th>
                    <th>Definition</th>
                    <th>Sample</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-if="samples.length === 0">
                    <td colspan="13" class="py-6 text-center text-sm text-base-content/60">
                      {{ page.empty_samples_message }}
                    </td>
                  </tr>
                  <tr
                    v-for="sample in samples"
                    :id="sample.id"
                    :key="sample.sample_id"
                    :class="sample.selected && 'bg-primary/10 outline outline-1 outline-primary/40'"
                    :data-explore-sample-id="sample.sample_id"
                    :data-explore-selected="sample.selected"
                  >
                    <td class="font-mono">{{ sample.receipt_time }}</td>
                    <td class="font-mono">{{ sample.generation_time }}</td>
                    <td class="font-mono">{{ sample.spacecraft_id }}</td>
                    <td class="font-mono">{{ sample.engineering_value }}</td>
                    <td class="font-mono">{{ sample.raw_value }}</td>
                    <td>{{ sample.quality_state }}</td>
                    <td><span class="badge badge-xs badge-outline">{{ sample.validity_state }}</span></td>
                    <td class="font-mono break-all" :data-explore-sample-source="sample.source_ref">{{ sample.source_ref }}</td>
                    <td class="font-mono break-all" :data-explore-sample-evidence="sample.evidence_id">{{ sample.evidence_display }}</td>
                    <td class="font-mono break-all" :data-explore-sample-packet="sample.packet_id">{{ sample.packet_display }}</td>
                    <td class="font-mono break-all" :data-explore-sample-definition="sample.packet_definition_id">{{ sample.packet_definition_ref }}</td>
                    <td class="font-mono break-all">{{ sample.sample_id }}</td>
                    <td class="text-right">
                      <a
                        v-if="sample.dashboard_href"
                        :href="sample.dashboard_href"
                        data-phx-link="redirect"
                        data-phx-link-state="push"
                        class="btn btn-ghost btn-xs"
                        title="Open in dashboard"
                        :data-explore-open-sample="sample.sample_id"
                      >
                        <span class="hero-arrow-top-right-on-square h-3.5 w-3.5" aria-hidden="true"></span>
                      </a>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </div>
    </div>
  </div>
</template>
