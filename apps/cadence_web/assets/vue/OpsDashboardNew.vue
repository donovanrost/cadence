<script setup lang="ts">
import {reactive, watch} from "vue"
import CadenceFormActions from "./ui/components/CadenceFormActions.vue"

type CloneSource = {
  id: string
  dashboard_id: string
  name: string
  widget_count: number
  latest_version: number
}

type Page = {
  id: string
  mode: "new" | "clone" | "import"
  eyebrow: string
  heading: string
  description: string
  source: CloneSource | null
  import_guidance: string | null
  cancel: {
    id: string
    label: string
    href: string
  }
}

type TextField = {
  id: string
  name: string
  type: "text"
  label: string
  value: string
  required: boolean
}

type DocumentJsonField = {
  id: string
  name: string
  type: "textarea"
  label: string
  value: string
  required: boolean
}

type DashboardForm = {
  id: string
  name: TextField
  description: TextField
  document_json: DocumentJsonField | null
  submit: {
    id: string
    label: string
  }
}

type DashboardValues = {
  name: string
  description: string
  document_json: string
}

type DashboardPayload = {
  dashboard: {
    name: string
    description: string
    document_json?: string
  }
}

const props = defineProps<{
  page: Page
  form: DashboardForm
}>()

const emit = defineEmits<{
  validate: [payload: DashboardPayload]
  save: [payload: DashboardPayload]
}>()

const valuesFromForm = (form: DashboardForm): DashboardValues => ({
  name: form.name.value,
  description: form.description.value,
  document_json: form.document_json?.value ?? ""
})

const dashboard = reactive<DashboardValues>(valuesFromForm(props.form))
const pendingValidations: DashboardValues[] = []

const values = (): DashboardValues => ({
  name: dashboard.name,
  description: dashboard.description,
  document_json: dashboard.document_json
})

const sameValues = (left: DashboardValues, right: DashboardValues) =>
  left.name === right.name &&
  left.description === right.description &&
  left.document_json === right.document_json

watch(
  () => props.form,
  (serverForm) => {
    const serverValues = valuesFromForm(serverForm)
    const acknowledgedIndex = pendingValidations.findIndex((sent) =>
      sameValues(sent, serverValues)
    )
    const latestPending = pendingValidations[pendingValidations.length - 1]
    const hasNewerTyping =
      acknowledgedIndex >= 0
        ? acknowledgedIndex < pendingValidations.length - 1
        : latestPending !== undefined && !sameValues(latestPending, serverValues)

    if (acknowledgedIndex >= 0) pendingValidations.splice(0, acknowledgedIndex + 1)

    if (!hasNewerTyping) Object.assign(dashboard, serverValues)
  },
  {deep: true}
)

const payload = (): DashboardPayload => {
  const dashboardValues: DashboardPayload["dashboard"] = {
    name: dashboard.name,
    description: dashboard.description
  }

  if (props.form.document_json !== null) {
    dashboardValues.document_json = dashboard.document_json
  }

  return {dashboard: dashboardValues}
}

const validate = () => {
  pendingValidations.push(values())
  emit("validate", payload())
}

const save = () => emit("save", payload())
</script>

<template>
  <section :id="page.id" class="h-full overflow-y-auto bg-base-100">
    <div class="mx-auto max-w-3xl px-6 py-12 lg:py-16">
      <div class="border-l-2 border-primary pl-4">
        <p class="font-mono text-[0.65rem] uppercase tracking-[0.2em] text-primary/70">
          {{ page.eyebrow }}
        </p>
        <h1 class="mt-1 text-2xl font-bold tracking-tight">{{ page.heading }}</h1>
        <p class="mt-2 max-w-2xl text-sm text-base-content/65">
          {{ page.description }}
        </p>
      </div>

      <div
        v-if="page.source !== null"
        :id="page.source.id"
        class="mt-6 border border-primary/20 bg-primary/5 p-3"
        :data-source-dashboard-id="page.source.dashboard_id"
      >
        <p class="hud-label">Source dashboard</p>
        <p class="mt-1 text-sm font-semibold">{{ page.source.name }}</p>
        <p class="mt-1 font-mono text-[0.65rem] text-base-content/45">
          {{ page.source.widget_count }} widgets · v{{ page.source.latest_version }}
        </p>
      </div>

      <form
        :id="form.id"
        class="mt-7 space-y-6 border border-base-300 bg-base-200/20 p-5"
        @submit.prevent="save"
      >
        <div class="fieldset mb-3">
          <label :for="form.name.id">
            <span class="hud-label block mb-1.5">{{ form.name.label }}</span>
            <input
              :id="form.name.id"
              v-model="dashboard.name"
              :name="form.name.name"
              :type="form.name.type"
              :required="form.name.required"
              class="w-full input"
              @input="validate"
            >
          </label>
        </div>

        <div class="fieldset mb-3">
          <label :for="form.description.id">
            <span class="hud-label block mb-1.5">{{ form.description.label }}</span>
            <input
              :id="form.description.id"
              v-model="dashboard.description"
              :name="form.description.name"
              :type="form.description.type"
              :required="form.description.required"
              class="w-full input"
              @input="validate"
            >
          </label>
        </div>

        <div v-if="form.document_json !== null" class="fieldset mb-3">
          <label :for="form.document_json.id">
            <span class="hud-label block mb-1.5">{{ form.document_json.label }}</span>
            <textarea
              :id="form.document_json.id"
              v-model="dashboard.document_json"
              :name="form.document_json.name"
              :required="form.document_json.required"
              class="textarea textarea-bordered min-h-80 w-full font-mono text-xs"
              @input="validate"
            ></textarea>
          </label>
        </div>

        <p v-if="page.import_guidance !== null" class="text-xs text-base-content/55">
          {{ page.import_guidance }}
        </p>

        <CadenceFormActions wrapper-class="flex items-center gap-3 border-t border-base-300/60 pt-5">
          <button :id="form.submit.id" type="submit" class="btn btn-primary">
            {{ form.submit.label }}
          </button>
          <a
            :id="page.cancel.id"
            :href="page.cancel.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="btn btn-ghost"
          >{{ page.cancel.label }}</a>
        </CadenceFormActions>
      </form>
    </div>
  </section>
</template>
