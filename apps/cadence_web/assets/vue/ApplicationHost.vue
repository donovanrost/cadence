<script setup lang="ts">
import {onBeforeUnmount, ref, watch} from "vue"

import ApplicationDiagnostics from "./application_host/ApplicationDiagnostics.vue"
import ApplicationNavigation from "./application_host/ApplicationNavigation.vue"
import ApplicationStats from "./application_host/ApplicationStats.vue"
import CadenceCard from "./ui/components/CadenceCard.vue"
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"
import type {
  Diagnostics,
  Navigation,
  Stat,
  StatusTone
} from "./application_host/presentation_types"
import StatusBadge from "./StatusBadge.vue"

type PacketGroupState = "available" | "selected" | "invalid" | "unavailable"

type Host = {
  dom_id: string
  application_key: string
  application_version: number
  application_installation_id: string
  surface_id: string
  renderer: "trusted" | "declarative"
}

type Confirmation = {
  title: string
  message: string
  confirm_label: string
  tone: "attention" | "danger"
  prompt: string
}

type DomainAction = {
  id: string
  action_id: string
  label: string
  version: number
  intent: string
  scope: string
  effect: string
  execution: string
  confirmation: Confirmation | null
  disabled: boolean
}

type ActionFeedback = {
  id: string
  role: "alert" | "status"
  kind: "success" | "error"
  code: string
  label: string
  message: string
}

type FormOption = {
  label: string
  value: string
  disabled: boolean
  description?: string | null
}

type Reference = {
  provider_id: string
  version: number
  mode: "select" | "search"
  query: string
  result_limit: number
  options_id: string
  status_id: string
  match_count: number
  more_matches: boolean
  debounce_ms: number
  max_length: number
  result_summary: string
  options: FormOption[]
}

type GeneratedFormField = {
  id: string
  field: string
  input_id: string
  name: string
  type: "text" | "textarea" | "number" | "url" | "select"
  contract_type: string
  label: string
  placeholder: string | null
  help: string | null
  required: boolean
  step: string | null
  min: number | null
  max: number | null
  value: string
  errors: string[]
  options: FormOption[]
  reference: Reference | null
  visible_when: {field: string; equals: string} | null
}

type GeneratedForm = {
  id: string
  form_id: string
  title: string
  description: string | null
  fields: GeneratedFormField[]
  action: DomainAction
}

type BasicFormField = {
  id: string
  field: string
  name: string
  type: string
  value: string
  errors: string[]
}

type PacketSourceEndpoint = BasicFormField & {
  label: string
  disabled: boolean
  options: FormOption[]
}

type PacketBindings = {
  id: string
  activation_state: string
  tone: StatusTone
  tone_label: string
  state_label: string
  title: string
  description: string | null
  configured_version_label: string
  applied_version_label: string
  save_enabled: boolean
  application_display_name: string
  form: {
    id: string
    hidden_fields: BasicFormField[]
    source_endpoint: PacketSourceEndpoint
    selected_packet_ids: string[]
  }
  action: DomainAction
  instructions: {
    shared_input: string
    save_status: string
  }
  empty: {
    id: string
    title: string
    description: string | null
  }
}

type TableColumn = {
  key: string
  label: string
  mono: boolean
}

type SurfaceTable = {
  id: string
  rows_id: string
  title: string
  description: string | null
  columns: TableColumn[]
  empty: {
    id: string
    title: string
    description: string | null
  }
  pagination: {
    id: string
    visible: boolean
    page: number
    page_size: number
    total_count: number
    range_label: string
    previous_label: string
    next_label: string
    previous_page: number
    next_page: number
    previous_disabled: boolean
    next_disabled: boolean
  }
}

type SurfaceActivity = {
  id: string
  items_id: string
  title: string
  description: string | null
  empty: {
    id: string
    title: string
    description: string | null
  }
}

type DeclarativeSurface = {
  id: string
  page: {
    title: string
    subtitle: string | null
  }
  action_feedback: ActionFeedback | null
  stats: Stat[]
  diagnostics: Diagnostics | null
  form: GeneratedForm | null
  packet_bindings: PacketBindings | null
  table: SurfaceTable | null
  activity: SurfaceActivity | null
}

type SurfaceRow = {
  id: string
  __dom_id: string
  values: Record<string, string>
}

type ActivityItem = {
  id: string
  __dom_id: string
  title: string
  detail: string
  value: string | null
  timestamp: string | null
  tone: StatusTone
  tone_label: string
}

type PacketResource = {
  id: string
  resource_id: string
  path: string
  resource_kind: string
  data_type: string | null
  size_bits: number | null
  compatibility: "compatible" | "incompatible"
  reason: string | null
  selected: boolean
  role: string
  consumers: string[]
  type_label: string
  size_label: string
  consumer_label: string
  selection_label: string
}

type PacketGroup = {
  id: string
  __dom_id: string
  packet_id: string
  packet_name: string
  apid: number
  selector_summary: string
  model_label: string
  selected: boolean
  expanded: boolean
  selectable: boolean
  state: PacketGroupState
  reason: string | null
  consumers: string[]
  resources: PacketResource[]
}

const props = defineProps<{
  host: Host
  navigation: Navigation | null
  declarative_surface: DeclarativeSurface | null
  application_surface_rows: SurfaceRow[]
  application_surface_activity: ActivityItem[]
  application_surface_packet_groups: PacketGroup[]
}>()

const emit = defineEmits<{
  application_form_change: [
    payload: {
      application_action: Record<string, string>
      _target?: string[]
    }
  ]
  application_action: [
    payload: {
      "action-id": string
      application_action: Record<string, string | string[]>
    }
  ]
  application_table_page: [payload: {page: string}]
}>()

const formValues = ref<Record<string, string>>({})
const packetValues = ref<Record<string, string>>({})
const selectedPacketIds = ref<string[]>([])
const searchTimers = new Map<string, ReturnType<typeof setTimeout>>()

watch(
  () => props.declarative_surface?.form?.fields,
  (fields) => {
    formValues.value = Object.fromEntries((fields ?? []).map((field) => [field.field, field.value]))
  },
  {deep: true, immediate: true}
)

watch(
  () => props.declarative_surface?.packet_bindings?.form,
  (form) => {
    if (!form) {
      packetValues.value = {}
      selectedPacketIds.value = []
      return
    }

    packetValues.value = Object.fromEntries([
      ...form.hidden_fields.map((field) => [field.field, field.value]),
      [form.source_endpoint.field, form.source_endpoint.value]
    ])
    selectedPacketIds.value = [...form.selected_packet_ids]
  },
  {deep: true, immediate: true}
)

const clearSearchTimers = () => {
  for (const timer of searchTimers.values()) clearTimeout(timer)
  searchTimers.clear()
}

onBeforeUnmount(clearSearchTimers)

const fieldVisible = (field: GeneratedFormField) => {
  if (!field.visible_when) return true
  return formValues.value[field.visible_when.field] === field.visible_when.equals
}

const emitFormChange = (field: GeneratedFormField) => {
  emit("application_form_change", {
    application_action: {...formValues.value},
    _target: ["application_action", field.field]
  })
}

const changeFormField = (field: GeneratedFormField, event: Event) => {
  const target = event.target as HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement
  formValues.value[field.field] = target.value

  const existingTimer = searchTimers.get(field.field)
  if (existingTimer) clearTimeout(existingTimer)

  if (field.reference?.mode === "search") {
    searchTimers.set(
      field.field,
      setTimeout(() => {
        searchTimers.delete(field.field)
        emitFormChange(field)
      }, field.reference.debounce_ms)
    )
  } else {
    emitFormChange(field)
  }
}

const confirmAction = (action: DomainAction) => {
  if (!action.confirmation) return true
  return window.confirm(action.confirmation.prompt)
}

const submitGeneratedForm = (form: GeneratedForm) => {
  if (form.action.disabled || !confirmAction(form.action)) return
  clearSearchTimers()

  emit("application_action", {
    "action-id": form.action.action_id,
    application_action: {...formValues.value}
  })
}

const changePacketValue = (field: string, event: Event) => {
  const target = event.target as HTMLSelectElement
  packetValues.value[field] = target.value
}

const changePacketSelection = (packetId: string, event: Event) => {
  const target = event.target as HTMLInputElement
  const selected = new Set(selectedPacketIds.value)

  if (target.checked) selected.add(packetId)
  else selected.delete(packetId)

  selectedPacketIds.value = [...selected]
}

const submitPacketBindings = (bindings: PacketBindings) => {
  if (bindings.action.disabled || !confirmAction(bindings.action)) return

  emit("application_action", {
    "action-id": bindings.action.action_id,
    application_action: {
      ...packetValues.value,
      selected_packet_ids: [...selectedPacketIds.value]
    }
  })
}

const paginate = (page: number) => emit("application_table_page", {page: String(page)})

const feedbackClasses = {
  success: "text-success",
  error: "text-error"
}

const feedbackRailClasses = {
  success: "bg-success",
  error: "bg-error"
}

const feedbackIcons = {
  success: "hero-check-circle",
  error: "hero-exclamation-triangle"
}

const activityRailClasses: Record<StatusTone, string> = {
  blocked: "bg-error",
  attention: "bg-warning",
  ready: "bg-success",
  info: "bg-info"
}

const packetRailClasses: Record<PacketGroupState, string> = {
  selected: "bg-primary",
  invalid: "bg-error",
  unavailable: "bg-base-content/20",
  available: "bg-base-content/35"
}
</script>

<template>
  <div
    class="contents"
    :data-application-host="host.dom_id"
    :data-host-renderer="host.renderer"
  >
  <ApplicationNavigation v-if="navigation" :navigation="navigation" />

  <div v-if="declarative_surface" :id="declarative_surface.id" class="space-y-6">
    <CadencePageHeaderFrame variant="compact">
      <h1 class="text-2xl font-bold tracking-tight text-base-content">
        {{ declarative_surface.page.title }}
      </h1>
      <p
        v-if="declarative_surface.page.subtitle"
        class="mt-1 max-w-3xl text-sm text-base-content/70"
      >{{ declarative_surface.page.subtitle }}</p>
    </CadencePageHeaderFrame>

    <aside
      v-if="declarative_surface.action_feedback"
      :id="declarative_surface.action_feedback.id"
      :role="declarative_surface.action_feedback.role"
      aria-live="polite"
      :data-kind="declarative_surface.action_feedback.kind"
      :data-code="declarative_surface.action_feedback.code"
      class="grid grid-cols-[0.3rem_auto_minmax(0,1fr)] items-center gap-4 border-y border-base-300/70 bg-base-200/45 px-4 py-3"
      :class="feedbackClasses[declarative_surface.action_feedback.kind]"
    >
      <span
        class="h-full min-h-10 rounded-full"
        :class="feedbackRailClasses[declarative_surface.action_feedback.kind]"
      ></span>
      <span
        class="size-5"
        :class="feedbackIcons[declarative_surface.action_feedback.kind]"
        aria-hidden="true"
      ></span>
      <div class="text-base-content">
        <p class="hud-label">{{ declarative_surface.action_feedback.label }}</p>
        <p class="mt-1 text-sm text-base-content/75">
          {{ declarative_surface.action_feedback.message }}
        </p>
      </div>
    </aside>

    <ApplicationStats
      v-if="declarative_surface.stats.length > 0"
      :stats="declarative_surface.stats"
    />

    <ApplicationDiagnostics
      v-if="declarative_surface.diagnostics"
      :diagnostics="declarative_surface.diagnostics"
    />

    <CadenceCard
      v-if="declarative_surface.form"
      :id="declarative_surface.form.id"
      class="card border border-base-300 bg-base-200"
      body-class="card-body p-6"
    >
        <div>
          <h2 class="text-base font-semibold">{{ declarative_surface.form.title }}</h2>
          <p
            v-if="declarative_surface.form.description"
            class="mt-1 text-sm text-base-content/60"
          >{{ declarative_surface.form.description }}</p>
        </div>

        <form
          :id="declarative_surface.form.form_id"
          class="mt-5"
          @submit.prevent="submitGeneratedForm(declarative_surface.form)"
        >
          <div class="grid gap-x-4 md:grid-cols-2">
            <div
              v-for="field in declarative_surface.form.fields"
              v-show="fieldVisible(field)"
              :id="field.id"
              :key="field.field"
              :data-field-type="field.contract_type"
              :data-reference-provider="field.reference?.provider_id"
              :data-reference-version="field.reference?.version"
              :data-reference-mode="field.reference?.mode"
              :data-reference-query="field.reference?.query"
            >
              <div class="fieldset mb-3">
                <label>
                  <span class="hud-label mb-1.5 block">{{ field.label }}</span>
                  <select
                    v-if="field.type === 'select'"
                    :id="field.input_id"
                    :name="field.name"
                    :required="field.required"
                    class="select w-full"
                    :class="field.errors.length > 0 && 'select-error'"
                    :value="formValues[field.field]"
                    @change="changeFormField(field, $event)"
                  >
                    <option v-if="field.placeholder" value="">{{ field.placeholder }}</option>
                    <option
                      v-for="option in field.options"
                      :key="option.value"
                      :value="option.value"
                      :disabled="option.disabled"
                      :title="option.description ?? undefined"
                    >{{ option.label }}</option>
                  </select>
                  <textarea
                    v-else-if="field.type === 'textarea'"
                    :id="field.input_id"
                    :name="field.name"
                    :placeholder="field.placeholder ?? undefined"
                    :required="field.required"
                    class="textarea min-h-24 w-full"
                    :class="field.errors.length > 0 && 'textarea-error'"
                    :value="formValues[field.field]"
                    @input="changeFormField(field, $event)"
                  ></textarea>
                  <input
                    v-else
                    :id="field.input_id"
                    :name="field.name"
                    :type="field.type"
                    :value="formValues[field.field]"
                    :placeholder="field.placeholder ?? undefined"
                    :required="field.required"
                    :step="field.step ?? undefined"
                    :min="field.min ?? undefined"
                    :max="field.max ?? undefined"
                    :list="field.reference?.mode === 'search' ? field.reference.options_id : undefined"
                    :maxlength="field.reference?.mode === 'search' ? field.reference.max_length : undefined"
                    :autocomplete="field.reference?.mode === 'search' ? 'off' : undefined"
                    :phx-debounce="field.reference?.mode === 'search'
                      ? String(field.reference.debounce_ms)
                      : undefined"
                    class="input w-full"
                    :class="[
                      field.reference?.mode === 'search' && 'font-mono text-sm',
                      field.errors.length > 0 && 'input-error'
                    ]"
                    @input="changeFormField(field, $event)"
                  />
                </label>

                <datalist v-if="field.reference?.mode === 'search'" :id="field.reference.options_id">
                  <option
                    v-for="option in field.reference.options"
                    :key="option.value"
                    :value="option.value"
                    :label="option.label"
                  >{{ option.description }}</option>
                </datalist>

                <p
                  v-if="field.reference?.mode === 'search'"
                  :id="field.reference.status_id"
                  :data-match-count="field.reference.match_count"
                  :data-more-matches="String(field.reference.more_matches)"
                  aria-live="polite"
                  class="-mt-1 mb-2 flex items-center gap-1.5 border-l-2 border-primary/45 pl-2 font-mono text-[0.68rem] uppercase tracking-[0.09em] text-base-content/55"
                >
                  <span class="hero-magnifying-glass size-3.5 text-primary/70" aria-hidden="true"></span>
                  {{ field.reference.result_summary }}
                </p>

                <p
                  v-for="error in field.errors"
                  :key="error"
                  class="mt-1.5 text-sm text-error"
                >{{ error }}</p>
              </div>
              <p
                v-if="field.help"
                class="mb-3 text-xs text-base-content/55"
                :class="field.reference?.mode === 'search' ? 'mt-1' : '-mt-1'"
              >{{ field.help }}</p>
            </div>
          </div>

          <button
            :id="declarative_surface.form.action.id"
            type="submit"
            class="btn btn-primary"
            :data-application-domain-action="declarative_surface.form.action.action_id"
            :data-action-version="declarative_surface.form.action.version"
            :data-action-intent="declarative_surface.form.action.intent"
            :data-action-scope="declarative_surface.form.action.scope"
            :data-action-effect="declarative_surface.form.action.effect"
            :data-action-execution="declarative_surface.form.action.execution"
            :data-confirmation-required="String(Boolean(declarative_surface.form.action.confirmation))"
            :data-confirmation-tone="declarative_surface.form.action.confirmation?.tone"
            :data-confirmation-title="declarative_surface.form.action.confirmation?.title"
            :data-confirmation-label="declarative_surface.form.action.confirmation?.confirm_label"
            :data-confirm="declarative_surface.form.action.confirmation?.prompt"
            :disabled="declarative_surface.form.action.disabled"
          >{{ declarative_surface.form.action.label }}</button>
        </form>
    </CadenceCard>

    <section
      v-if="declarative_surface.packet_bindings"
      :id="declarative_surface.packet_bindings.id"
      :data-activation-state="declarative_surface.packet_bindings.activation_state"
      class="overflow-hidden border-y border-base-300/80 bg-base-100"
    >
      <header class="grid gap-4 border-b border-base-300/70 bg-base-200/35 px-4 py-4 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-end">
        <div>
          <div class="flex flex-wrap items-center gap-2">
            <p class="hud-label">Packet input routing</p>
            <StatusBadge
              :status="declarative_surface.packet_bindings.tone"
              :label="declarative_surface.packet_bindings.tone_label"
            />
            <span class="font-mono text-[0.68rem] uppercase tracking-[0.12em] text-base-content/45">
              {{ declarative_surface.packet_bindings.state_label }}
            </span>
          </div>
          <h2 class="mt-2 text-lg font-semibold tracking-tight">
            {{ declarative_surface.packet_bindings.title }}
          </h2>
          <p
            v-if="declarative_surface.packet_bindings.description"
            class="mt-1 max-w-4xl text-sm text-base-content/60"
          >{{ declarative_surface.packet_bindings.description }}</p>
        </div>
        <div class="flex items-center gap-3 font-mono text-[0.7rem] uppercase tracking-[0.1em] text-base-content/50">
          <span>Desired {{ declarative_surface.packet_bindings.configured_version_label }}</span>
          <span aria-hidden="true">·</span>
          <span>Active {{ declarative_surface.packet_bindings.applied_version_label }}</span>
        </div>
      </header>

      <form
        :id="declarative_surface.packet_bindings.form.id"
        @submit.prevent="submitPacketBindings(declarative_surface.packet_bindings)"
      >
        <input
          v-for="field in declarative_surface.packet_bindings.form.hidden_fields"
          :id="field.id"
          :key="field.field"
          type="hidden"
          :name="field.name"
          :value="packetValues[field.field]"
        />

        <div class="grid gap-4 border-b border-base-300/60 px-4 py-3 md:grid-cols-[minmax(16rem,28rem)_1fr] md:items-end">
          <div class="fieldset mb-3">
            <label>
              <span class="hud-label mb-1.5 block">
                {{ declarative_surface.packet_bindings.form.source_endpoint.label }}
              </span>
              <select
                :id="declarative_surface.packet_bindings.form.source_endpoint.id"
                :name="declarative_surface.packet_bindings.form.source_endpoint.name"
                :value="packetValues[declarative_surface.packet_bindings.form.source_endpoint.field]"
                :disabled="declarative_surface.packet_bindings.form.source_endpoint.disabled"
                class="select w-full font-mono text-sm"
                @change="changePacketValue(
                  declarative_surface.packet_bindings.form.source_endpoint.field,
                  $event
                )"
              >
                <option
                  v-for="option in declarative_surface.packet_bindings.form.source_endpoint.options"
                  :key="option.value"
                  :value="option.value"
                  :disabled="option.disabled"
                >{{ option.label }}</option>
              </select>
            </label>
          </div>
          <p class="pb-3 text-xs text-base-content/50">
            {{ declarative_surface.packet_bindings.instructions.shared_input }}
          </p>
        </div>

        <div id="packet-binding-groups" phx-update="stream" class="divide-y divide-base-300/65">
          <div
            :id="declarative_surface.packet_bindings.empty.id"
            class="hidden only:block px-4 py-12 text-center"
          >
            <span class="hero-signal-slash mx-auto size-6 text-base-content/35" aria-hidden="true"></span>
            <p class="mt-3 font-medium">{{ declarative_surface.packet_bindings.empty.title }}</p>
            <p
              v-if="declarative_surface.packet_bindings.empty.description"
              class="mt-1 text-sm text-base-content/55"
            >{{ declarative_surface.packet_bindings.empty.description }}</p>
          </div>

          <details
            v-for="group in application_surface_packet_groups"
            :id="group.__dom_id"
            :key="group.id"
            :open="group.expanded"
            :data-packet-id="group.packet_id"
            :data-apid="group.apid"
            :data-state="group.state"
            class="group relative"
          >
            <summary class="grid cursor-pointer list-none grid-cols-[0.25rem_minmax(0,1fr)_auto] items-stretch gap-4 px-4 py-3 marker:hidden hover:bg-base-200/30">
              <span class="rounded-full" :class="packetRailClasses[group.state]"></span>
              <div class="min-w-0">
                <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
                  <span class="font-mono text-[0.68rem] font-semibold uppercase tracking-[0.13em] text-primary/80">
                    APID {{ group.apid }}
                  </span>
                  <strong class="truncate font-mono text-sm">{{ group.packet_name }}</strong>
                  <span class="text-xs text-base-content/45">{{ group.model_label }}</span>
                </div>
                <p class="mt-1 truncate font-mono text-[0.68rem] text-base-content/45">
                  {{ group.selector_summary }}
                </p>
              </div>
              <div class="flex items-center gap-3 pl-3">
                <span
                  v-if="group.consumers.length > 0"
                  class="hidden text-xs text-base-content/50 sm:inline"
                >{{ group.consumers.join(', ') }}</span>
                <label
                  :for="`packet-binding-select-${group.packet_id}`"
                  class="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.08em]"
                  :class="group.selectable ? 'cursor-pointer' : 'cursor-not-allowed text-base-content/35'"
                  @click.stop
                >
                  <input
                    :id="`packet-binding-select-${group.packet_id}`"
                    type="checkbox"
                    name="application_action[selected_packet_ids][]"
                    :value="group.packet_id"
                    :aria-label="`Route ${group.packet_name}, APID ${group.apid}, into ${declarative_surface.packet_bindings.application_display_name}`"
                    :checked="selectedPacketIds.includes(group.packet_id)"
                    :disabled="!group.selectable || !declarative_surface.packet_bindings.save_enabled"
                    class="checkbox checkbox-primary checkbox-sm"
                    @change="changePacketSelection(group.packet_id, $event)"
                  />
                  Route
                </label>
                <span
                  class="hero-chevron-down size-4 text-base-content/45 transition-transform group-open:rotate-180"
                  aria-hidden="true"
                ></span>
              </div>
            </summary>

            <div class="border-t border-base-300/50 bg-base-200/20 px-4 pb-4 pl-8 pt-3">
              <p v-if="group.reason" class="mb-3 text-xs text-warning">{{ group.reason }}</p>
              <div class="overflow-x-auto">
                <table class="table table-xs">
                  <thead>
                    <tr>
                      <th>Resource</th>
                      <th>Type</th>
                      <th>Size</th>
                      <th>Consumers</th>
                      <th>This app</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      v-for="resource in group.resources"
                      :id="resource.id"
                      :key="resource.resource_id"
                      :data-resource-kind="resource.resource_kind"
                      :data-compatibility="resource.compatibility"
                      :class="resource.resource_kind === 'binary_region' && 'border-l-4 border-l-base-content/25'"
                    >
                      <td>
                        <p class="font-mono text-xs">{{ resource.path }}</p>
                        <p
                          v-if="resource.reason"
                          class="mt-1 max-w-xl text-[0.68rem] text-base-content/45"
                        >{{ resource.reason }}</p>
                      </td>
                      <td class="font-mono text-xs">{{ resource.type_label }}</td>
                      <td class="font-mono text-xs text-base-content/55">{{ resource.size_label }}</td>
                      <td class="text-xs text-base-content/55">{{ resource.consumer_label }}</td>
                      <td>
                        <span
                          class="badge badge-sm"
                          :class="[
                            resource.selected && 'badge-primary',
                            !resource.selected && resource.compatibility === 'compatible' && 'badge-ghost',
                            resource.compatibility === 'incompatible' && 'badge-outline opacity-50'
                          ]"
                        >{{ resource.selection_label }}</span>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </details>
        </div>

        <footer class="flex flex-wrap items-center justify-between gap-4 border-t border-base-300/70 bg-base-200/30 px-4 py-3">
          <p id="packet-bindings-status" aria-live="polite" class="text-xs text-base-content/50">
            {{ declarative_surface.packet_bindings.instructions.save_status }}
          </p>
          <button
            :id="declarative_surface.packet_bindings.action.id"
            type="submit"
            class="btn btn-primary"
            :data-application-domain-action="declarative_surface.packet_bindings.action.action_id"
            :data-action-version="declarative_surface.packet_bindings.action.version"
            :data-action-intent="declarative_surface.packet_bindings.action.intent"
            :data-action-scope="declarative_surface.packet_bindings.action.scope"
            :data-action-effect="declarative_surface.packet_bindings.action.effect"
            :data-action-execution="declarative_surface.packet_bindings.action.execution"
            :data-confirmation-required="String(Boolean(declarative_surface.packet_bindings.action.confirmation))"
            :data-confirmation-tone="declarative_surface.packet_bindings.action.confirmation?.tone"
            :data-confirmation-title="declarative_surface.packet_bindings.action.confirmation?.title"
            :data-confirmation-label="declarative_surface.packet_bindings.action.confirmation?.confirm_label"
            :data-confirm="declarative_surface.packet_bindings.action.confirmation?.prompt"
            :disabled="declarative_surface.packet_bindings.action.disabled"
          >{{ declarative_surface.packet_bindings.action.label }}</button>
        </footer>
      </form>
    </section>

    <section
      v-if="declarative_surface.table"
      :id="declarative_surface.table.id"
      class="card border border-base-300 bg-base-200"
    >
      <div class="px-4 pt-4">
        <h2 class="text-base font-semibold">{{ declarative_surface.table.title }}</h2>
        <p
          v-if="declarative_surface.table.description"
          class="mt-1 text-sm text-base-content/60"
        >{{ declarative_surface.table.description }}</p>
      </div>

      <div class="mt-5 overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr>
              <th v-for="column in declarative_surface.table.columns" :key="column.key">
                {{ column.label }}
              </th>
            </tr>
          </thead>
          <tbody :id="declarative_surface.table.rows_id" phx-update="stream">
            <tr :id="declarative_surface.table.empty.id" class="hidden only:table-row">
              <td :colspan="declarative_surface.table.columns.length">
                <div class="py-8 text-center">
                  <p class="font-medium">{{ declarative_surface.table.empty.title }}</p>
                  <p
                    v-if="declarative_surface.table.empty.description"
                    class="mt-1 text-sm text-base-content/60"
                  >{{ declarative_surface.table.empty.description }}</p>
                </div>
              </td>
            </tr>
            <tr
              v-for="row in application_surface_rows"
              :id="row.__dom_id"
              :key="row.id"
            >
              <td
                v-for="column in declarative_surface.table.columns"
                :key="column.key"
                :class="column.mono && 'font-mono text-xs'"
              >{{ row.values[column.key] }}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div
        v-if="declarative_surface.table.pagination.visible"
        :id="declarative_surface.table.pagination.id"
        class="flex items-center justify-between border-t border-base-300 px-4 py-2"
      >
        <span class="font-mono text-xs text-base-content/70">
          {{ declarative_surface.table.pagination.range_label }}
        </span>
        <div class="flex items-center gap-1">
          <button
            type="button"
            class="btn btn-ghost btn-xs"
            :phx-value-page="declarative_surface.table.pagination.previous_page"
            :disabled="declarative_surface.table.pagination.previous_disabled"
            @click="paginate(declarative_surface.table.pagination.previous_page)"
          >{{ declarative_surface.table.pagination.previous_label }}</button>
          <button
            type="button"
            class="btn btn-ghost btn-xs"
            :phx-value-page="declarative_surface.table.pagination.next_page"
            :disabled="declarative_surface.table.pagination.next_disabled"
            @click="paginate(declarative_surface.table.pagination.next_page)"
          >{{ declarative_surface.table.pagination.next_label }}</button>
        </div>
      </div>
    </section>

    <CadenceCard
      v-if="declarative_surface.activity"
      :id="declarative_surface.activity.id"
      class="card border border-base-300 bg-base-200"
      body-class="card-body p-6"
    >
        <div>
          <h2 class="text-base font-semibold">{{ declarative_surface.activity.title }}</h2>
          <p
            v-if="declarative_surface.activity.description"
            class="mt-1 text-sm text-base-content/60"
          >{{ declarative_surface.activity.description }}</p>
        </div>

        <div
          :id="declarative_surface.activity.items_id"
          class="mt-5 divide-y divide-base-300/60 border-y border-base-300/60"
          phx-update="stream"
        >
          <div :id="declarative_surface.activity.empty.id" class="hidden only:block py-8 text-center">
            <p class="font-medium">{{ declarative_surface.activity.empty.title }}</p>
            <p
              v-if="declarative_surface.activity.empty.description"
              class="mt-1 text-sm text-base-content/60"
            >{{ declarative_surface.activity.empty.description }}</p>
          </div>
          <article
            v-for="item in application_surface_activity"
            :id="item.__dom_id"
            :key="item.id"
            class="group grid grid-cols-[0.35rem_minmax(0,1fr)_auto] gap-4 py-4"
          >
            <div
              class="rounded-full transition-transform duration-200 group-hover:scale-y-110"
              :class="activityRailClasses[item.tone]"
            ></div>
            <div class="min-w-0">
              <div class="flex flex-wrap items-center gap-2">
                <h3 class="truncate font-medium text-base-content">{{ item.title }}</h3>
                <StatusBadge :status="item.tone" :label="item.tone_label" />
              </div>
              <p class="mt-1 text-xs uppercase tracking-[0.12em] text-base-content/55">
                {{ item.detail }}
              </p>
              <time
                v-if="item.timestamp"
                class="mt-2 block font-mono text-[0.7rem] text-base-content/45"
              >{{ item.timestamp }}</time>
            </div>
            <p v-if="item.value" class="self-center font-mono text-lg text-base-content">
              {{ item.value }}
            </p>
          </article>
        </div>
    </CadenceCard>
  </div>
  </div>
</template>
