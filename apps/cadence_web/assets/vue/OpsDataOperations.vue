<script setup lang="ts">
import {reactive, watch} from "vue"

type NavigationAction = {
  id: string
  label: string
  href: string
}

type Page = {
  id: string
  selected_group_id: string | null
  groups_empty: boolean
  navigation: {
    manage?: NavigationAction
    reader?: NavigationAction
  }
}

type Option = {
  label: string
  value: string
}

type RequestField = {
  id: string
  name: string
  type: "text" | "select" | "checkbox"
  label: string
  placeholder: string | null
  options: Option[]
}

type RequestValues = Record<string, string>

type RequestForm = {
  id: string
  values: RequestValues
  fields: {
    workflow: RequestField
    run_id: RequestField
    realm: RequestField
    data_source_id: RequestField
    source_binding_id: RequestField
    point_ids: RequestField
    source_from: RequestField
    source_to: RequestField
    reason: RequestField
    confirmed: RequestField
  }
  hidden_fields: Array<{
    name: string
    value_key: string
  }>
  error: {
    id: string
    message: string
  } | null
  submit: {
    id: string
    label: string
  }
}

type DataOperationGroup = {
  __dom_id: string
  id: string
  href: string
  state: string
  workflow: string
  size: number
  progress: string
}

type Action = {
  id: string
  label: string
  confirm: string
  payload: Record<string, string>
}

type Failure = {
  label: string | null
  recovery_action: string
  correction?: Action
}

type SelectedGroup = {
  id: string
  workflow: string
  state: string
  context: {
    realm: string
    data_source_id: string
    binding_id: string
  }
  progress: Array<{
    label: string
    value: number
  }>
  affected_dashboards: Array<{
    id: string
    label: string
    href: string
  }>
  comparison_reviews: Array<{
    id: string
    request_event_id: string
    request_kind: string
    open_count: string
    open_placement_ids: string
  }>
  audit_events: Array<{
    id: string
    event_type: string
    reason: string
    occurred_at: string
  }>
  recovery?: {
    transitions: Action[]
    retry: Action | null
    failures: Failure[]
  }
}

const props = defineProps<{
  page: Page
  request_form: RequestForm
  selected_group: SelectedGroup | null
  data_operation_groups: DataOperationGroup[]
}>()

const emit = defineEmits<{
  "validate-request": [payload: {historical_workflow_request: RequestValues}]
  "record-historical-workflow-request": [payload: {historical_workflow_request: RequestValues}]
  "transition-group": [payload: {"group-id": string; stage: string}]
  "retry-group": [payload: {"group-id": string}]
  "request-correction": [payload: {"group-id": string; "event-id": string}]
}>()

const primaryRequestFieldKeys = [
  "run_id",
  "realm",
  "data_source_id",
  "source_binding_id",
  "point_ids"
] as const

const sourceRangeFieldKeys = ["source_from", "source_to"] as const

const requestValues = reactive<RequestValues>({...props.request_form.values})
const pendingValidations: RequestValues[] = []

const checked = (value: string) => ["true", "on", "confirmed"].includes(value)

const normalizedValues = (values: RequestValues): RequestValues => {
  const normalized: RequestValues = {}

  for (const key of Object.keys(props.request_form.values)) {
    normalized[key] = String(values[key] ?? "")
  }

  normalized.confirmed = checked(normalized.confirmed) ? "true" : "false"
  return normalized
}

const sameValues = (left: RequestValues, right: RequestValues) =>
  JSON.stringify(left) === JSON.stringify(right)

watch(
  () => props.request_form.values,
  serverValues => {
    const normalizedServerValues = normalizedValues(serverValues)
    const acknowledgedIndex = pendingValidations.findIndex(values =>
      sameValues(values, normalizedServerValues)
    )
    const hasNewerTyping =
      acknowledgedIndex >= 0 && acknowledgedIndex < pendingValidations.length - 1

    if (acknowledgedIndex >= 0) pendingValidations.splice(0, acknowledgedIndex + 1)
    if (!hasNewerTyping) Object.assign(requestValues, normalizedServerValues)
  },
  {deep: true}
)

const validateRequest = () => {
  const values = normalizedValues(requestValues)
  pendingValidations.push(values)
  emit("validate-request", {historical_workflow_request: values})
}

const updateConfirmed = (event: Event) => {
  requestValues.confirmed = (event.target as HTMLInputElement).checked ? "true" : "false"
  validateRequest()
}

const recordRequest = () => {
  emit("record-historical-workflow-request", {
    historical_workflow_request: normalizedValues(requestValues)
  })
}

const statusBadgeClass = (state: string) => [
  "badge badge-xs font-mono",
  ["completed", "closed"].includes(state)
    ? "badge-success"
    : ["failed", "blocked"].includes(state)
      ? "badge-error"
      : ["started", "in_progress"].includes(state)
        ? "badge-info"
        : "badge-warning"
]

const transitionGroup = (action: Action) => {
  if (window.confirm(action.confirm)) {
    emit("transition-group", action.payload as {"group-id": string; stage: string})
  }
}

const retryGroup = (action: Action) => {
  if (window.confirm(action.confirm)) {
    emit("retry-group", action.payload as {"group-id": string})
  }
}

const requestCorrection = (action: Action) => {
  if (window.confirm(action.confirm)) {
    emit(
      "request-correction",
      action.payload as {"group-id": string; "event-id": string}
    )
  }
}
</script>

<template>
  <main :id="page.id" class="min-h-0 flex-1 overflow-y-auto">
    <div class="mx-auto max-w-[96rem] space-y-5 px-5 py-6">
      <header
        class="flex flex-col gap-3 border-b border-primary/20 pb-4 lg:flex-row lg:items-end lg:justify-between"
      >
        <div>
          <p class="hud-label">System / Historical data plane</p>
          <h1 class="mt-1 text-xl font-semibold tracking-tight">Data Operations</h1>
          <p class="mt-1 max-w-3xl text-sm text-base-content/60">
            Request, follow, correct, and close historical telemetry repair without returning to the dashboard that exposed the gap.
          </p>
        </div>
        <nav aria-label="Data Operations view" class="flex flex-wrap gap-2">
          <a
            v-if="page.navigation.manage"
            :id="page.navigation.manage.id"
            :href="page.navigation.manage.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="btn btn-sm btn-outline"
          >
            <span class="hero-wrench-screwdriver h-4 w-4"></span>
            {{ page.navigation.manage.label }}
          </a>
          <a
            v-if="page.navigation.reader"
            :id="page.navigation.reader.id"
            :href="page.navigation.reader.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="btn btn-sm btn-ghost"
          >
            {{ page.navigation.reader.label }}
          </a>
        </nav>
      </header>

      <section class="grid min-h-[42rem] gap-4 xl:grid-cols-[22rem_minmax(0,1fr)_24rem]">
        <aside class="border border-base-300 bg-base-200/45" aria-label="Historical request groups">
          <div class="border-b border-base-300 px-3 py-2">
            <h2 class="hud-label">Request groups</h2>
          </div>
          <div id="data-operation-groups" class="divide-y divide-base-300">
            <div
              v-if="page.groups_empty"
              id="data-operation-groups-empty"
              class="hidden only:block p-5 text-sm text-base-content/50"
            >
              No historical data operations have been recorded for this mission.
            </div>
            <a
              v-for="group in data_operation_groups"
              :id="group.__dom_id"
              :key="group.id"
              :href="group.href"
              data-phx-link="patch"
              data-phx-link-state="push"
              :aria-current="page.selected_group_id === group.id ? 'page' : undefined"
              :class="[
                'block space-y-2 px-3 py-3 hover:bg-primary/5',
                page.selected_group_id === group.id && 'border-l-2 border-primary bg-primary/10'
              ]"
              :data-operation-state="group.state"
              :data-operation-workflow="group.workflow"
            >
              <div class="flex items-center justify-between gap-2">
                <span class="truncate font-mono text-xs font-semibold">{{ group.id }}</span>
                <span :class="statusBadgeClass(group.state)">{{ group.state }}</span>
              </div>
              <div class="flex items-center justify-between text-[0.6875rem] text-base-content/55">
                <span>{{ group.workflow }} · {{ group.size }} item(s)</span>
                <span>{{ group.progress }}</span>
              </div>
            </a>
          </div>
        </aside>

        <section id="data-operation-detail" class="min-w-0 border border-base-300 bg-base-100">
          <div
            v-if="selected_group === null"
            class="grid min-h-[34rem] place-items-center p-8 text-center"
          >
            <div class="max-w-sm">
              <span class="hero-circle-stack mx-auto h-8 w-8 text-base-content/30"></span>
              <h2 class="mt-3 text-sm font-semibold">Select an operation</h2>
              <p class="mt-1 text-sm text-base-content/55">
                Choose a request group to follow progress, affected dashboards, recovery, and audit evidence.
              </p>
            </div>
          </div>

          <div v-else class="space-y-5 p-5">
            <div
              class="flex flex-col gap-3 border-b border-base-300 pb-4 md:flex-row md:items-start md:justify-between"
            >
              <div class="min-w-0">
                <p class="hud-label">{{ selected_group.workflow }} request group</p>
                <h2
                  id="data-operation-group-id"
                  class="mt-1 break-all font-mono text-sm font-semibold"
                >
                  {{ selected_group.id }}
                </h2>
                <p class="mt-2 text-xs text-base-content/55">
                  {{ selected_group.context.realm }} · {{ selected_group.context.data_source_id }} · {{ selected_group.context.binding_id }}
                </p>
              </div>
              <span :class="statusBadgeClass(selected_group.state)">{{ selected_group.state }}</span>
            </div>

            <dl
              id="data-operation-progress"
              class="grid grid-cols-2 gap-px bg-base-300 sm:grid-cols-4"
            >
              <div
                v-for="progress in selected_group.progress"
                :key="progress.label"
                class="bg-base-100 px-3 py-3"
              >
                <dt class="hud-label">{{ progress.label }}</dt>
                <dd class="mt-1 font-mono text-lg font-semibold">{{ progress.value }}</dd>
              </div>
            </dl>

            <section id="data-operation-affected-dashboards" class="space-y-2">
              <h3 class="hud-label">Affected dashboards</h3>
              <p
                v-if="selected_group.affected_dashboards.length === 0"
                class="text-xs text-base-content/45"
              >
                No dashboard origin was recorded.
              </p>
              <div class="flex flex-wrap gap-2">
                <a
                  v-for="dashboard in selected_group.affected_dashboards"
                  :id="dashboard.id"
                  :key="dashboard.id"
                  :href="dashboard.href"
                  data-phx-link="redirect"
                  data-phx-link-state="push"
                  class="btn btn-xs btn-outline"
                >
                  <span class="hero-squares-2x2 h-3.5 w-3.5"></span>
                  {{ dashboard.label }}
                </a>
              </div>
            </section>

            <section id="data-operation-comparison-reviews" class="space-y-2">
              <h3 class="hud-label">Comparison & revision context</h3>
              <p
                v-if="selected_group.comparison_reviews.length === 0"
                class="text-xs text-base-content/45"
              >
                No comparison-review origin is attached.
              </p>
              <div
                v-for="review in selected_group.comparison_reviews"
                :id="review.id"
                :key="review.id"
                class="border border-base-300 bg-base-200/40 p-3 text-xs"
              >
                <p class="font-mono font-semibold">{{ review.request_event_id }}</p>
                <p class="mt-1 text-base-content/60">
                  {{ review.request_kind }} · {{ review.open_count }} open finding(s)
                </p>
                <p class="mt-1 font-mono text-base-content/45">{{ review.open_placement_ids }}</p>
              </div>
            </section>

            <section id="data-operation-audit" class="space-y-2">
              <h3 class="hud-label">Audit history</h3>
              <div class="divide-y divide-base-300 border border-base-300">
                <div
                  v-for="event in selected_group.audit_events"
                  :id="event.id"
                  :key="event.id"
                  class="grid gap-1 px-3 py-2 text-xs sm:grid-cols-[10rem_minmax(0,1fr)_12rem]"
                >
                  <span class="font-mono font-semibold">{{ event.event_type }}</span>
                  <span class="truncate text-base-content/60">{{ event.reason }}</span>
                  <time class="font-mono text-base-content/45 sm:text-right">{{ event.occurred_at }}</time>
                </div>
              </div>
            </section>
          </div>
        </section>

        <aside class="space-y-4">
          <section
            id="data-operation-request-panel"
            class="border border-base-300 bg-base-200/45 p-4"
          >
            <h2 class="hud-label">New historical request</h2>
            <p class="mt-1 text-xs text-base-content/55">
              Dashboard and Explore links prefill this same durable request.
            </p>
            <form
              :id="request_form.id"
              class="mt-4 space-y-3"
              @submit.prevent="recordRequest"
            >
              <div class="fieldset mb-3">
                <label :for="request_form.fields.workflow.id">
                  <span class="hud-label block mb-1.5">{{ request_form.fields.workflow.label }}</span>
                  <select
                    :id="request_form.fields.workflow.id"
                    v-model="requestValues.workflow"
                    :name="request_form.fields.workflow.name"
                    class="w-full select"
                    @change="validateRequest"
                  >
                    <option
                      v-for="option in request_form.fields.workflow.options"
                      :key="option.value"
                      :value="option.value"
                    >{{ option.label }}</option>
                  </select>
                </label>
              </div>

              <div
                v-for="fieldKey in primaryRequestFieldKeys"
                :key="request_form.fields[fieldKey].id"
                class="fieldset mb-3"
              >
                <label :for="request_form.fields[fieldKey].id">
                  <span class="hud-label block mb-1.5">{{ request_form.fields[fieldKey].label }}</span>
                  <input
                    :id="request_form.fields[fieldKey].id"
                    v-model="requestValues[fieldKey]"
                    :name="request_form.fields[fieldKey].name"
                    type="text"
                    :placeholder="request_form.fields[fieldKey].placeholder ?? undefined"
                    class="w-full input"
                    @input="validateRequest"
                  >
                </label>
              </div>

              <div class="grid grid-cols-2 gap-2">
                <div
                  v-for="fieldKey in sourceRangeFieldKeys"
                  :key="request_form.fields[fieldKey].id"
                  class="fieldset mb-3"
                >
                  <label :for="request_form.fields[fieldKey].id">
                    <span class="hud-label block mb-1.5">{{ request_form.fields[fieldKey].label }}</span>
                    <input
                      :id="request_form.fields[fieldKey].id"
                      v-model="requestValues[fieldKey]"
                      :name="request_form.fields[fieldKey].name"
                      type="text"
                      class="w-full input"
                      @input="validateRequest"
                    >
                  </label>
                </div>
              </div>

              <div class="fieldset mb-3">
                <label :for="request_form.fields.reason.id">
                  <span class="hud-label block mb-1.5">{{ request_form.fields.reason.label }}</span>
                  <input
                    :id="request_form.fields.reason.id"
                    v-model="requestValues.reason"
                    :name="request_form.fields.reason.name"
                    type="text"
                    class="w-full input"
                    @input="validateRequest"
                  >
                </label>
              </div>

              <div class="fieldset mb-3">
                <label class="flex cursor-pointer items-start gap-3">
                  <input
                    type="hidden"
                    :name="request_form.fields.confirmed.name"
                    value="false"
                  >
                  <input
                    :id="request_form.fields.confirmed.id"
                    :name="request_form.fields.confirmed.name"
                    type="checkbox"
                    value="true"
                    :checked="checked(requestValues.confirmed)"
                    class="checkbox checkbox-sm mt-0.5"
                    @change="updateConfirmed"
                  >
                  <span>
                    <span class="block text-sm font-medium">{{ request_form.fields.confirmed.label }}</span>
                  </span>
                </label>
              </div>

              <input
                v-for="field in request_form.hidden_fields"
                :key="field.name"
                type="hidden"
                :name="field.name"
                :value="requestValues[field.value_key]"
              >
              <p
                v-if="request_form.error"
                :id="request_form.error.id"
                class="text-xs text-error"
              >
                {{ request_form.error.message }}
              </p>
              <button
                :id="request_form.submit.id"
                type="submit"
                class="btn btn-sm btn-primary w-full"
              >
                <span class="hero-document-plus h-4 w-4"></span>
                {{ request_form.submit.label }}
              </button>
            </form>
          </section>

          <section
            v-if="selected_group?.recovery"
            id="data-operation-recovery-panel"
            class="border border-warning/35 bg-warning/5 p-4"
          >
            <h2 class="hud-label">Privileged workflow controls</h2>
            <p class="mt-1 text-xs text-base-content/55">
              Transitions and recovery write audit events and may change canonical historical telemetry.
            </p>
            <div class="mt-3 grid grid-cols-2 gap-2">
              <button
                v-for="action in selected_group.recovery.transitions"
                :id="action.id"
                :key="action.id"
                type="button"
                :data-confirm="action.confirm"
                class="btn btn-xs btn-outline"
                @click="transitionGroup(action)"
              >
                {{ action.label }}
              </button>
            </div>
            <button
              v-if="selected_group.recovery.retry"
              :id="selected_group.recovery.retry.id"
              type="button"
              :data-confirm="selected_group.recovery.retry.confirm"
              class="btn btn-xs btn-warning mt-3 w-full"
              @click="retryGroup(selected_group.recovery.retry)"
            >
              {{ selected_group.recovery.retry.label }}
            </button>
            <div v-if="selected_group.recovery.failures.length > 0" class="mt-3 space-y-2">
              <div
                v-for="(failure, index) in selected_group.recovery.failures"
                :key="`${failure.label}-${index}`"
                class="border border-base-300 bg-base-100 p-2 text-xs"
              >
                <p class="font-mono">{{ failure.label }}</p>
                <p class="mt-1 text-base-content/55">{{ failure.recovery_action }}</p>
                <button
                  v-if="failure.correction"
                  :id="failure.correction.id"
                  type="button"
                  :data-confirm="failure.correction.confirm"
                  class="btn btn-xs btn-outline mt-2"
                  @click="requestCorrection(failure.correction)"
                >
                  {{ failure.correction.label }}
                </button>
              </div>
            </div>
          </section>
        </aside>
      </section>
    </div>
  </main>
</template>
