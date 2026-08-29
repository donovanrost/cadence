<script setup lang="ts">
import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"
import CadenceField from "./ui/components/CadenceField.vue"
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"
import CadenceValidationMessage from "./ui/components/CadenceValidationMessage.vue"
import {reactive, watch} from "vue"

type Header = {
  id: string
  back: {
    id: string
    label: string
    icon: string
  }
  title: string
  copy: string
}

type PolicyRequired = {
  id: string
  icon: string
  title: string
  copy: string
  action_id: string
  action_label: string
}

type PolicyState = {
  active: boolean
  required: PolicyRequired | null
}

type DateTimeField = {
  id: string
  name: string
  type: "datetime-local"
  label: string
  required: boolean
  value: string
  errors: string[]
}

type CheckboxField = {
  id: string
  name: string
  type: "checkbox"
  label: string
  value: boolean
  errors: string[]
}

type FleetRunForm = {
  id: string
  fields: {
    horizon_start: DateTimeField
    horizon_end: DateTimeField
    include_recurring: CheckboxField
  }
  snapshot: {
    label: string
    copy: string
  }
  submit: {
    id: string
    label: string
  }
}

type PolicyPreview = {
  id: string
  eyebrow: string
  version: string
  facts: Array<{
    term: string
    value: string
  }>
  details: {
    id: string
    summary: string
    copy: string
  }
}

type Paths = {
  planning: string
  policy: string
}

type FleetRunValues = {
  horizon_start: string
  horizon_end: string
  include_recurring: boolean
}

type FleetRunPayload = {
  fleet_run: FleetRunValues
}

const props = defineProps<{
  header: Header
  policy_state: PolicyState
  form: FleetRunForm | null
  preview: PolicyPreview | null
  paths: Paths
}>()

const emit = defineEmits<{
  "validate-fleet-run": [payload: FleetRunPayload]
  "create-fleet-run": [payload: FleetRunPayload]
}>()

const valuesFromForm = (form: FleetRunForm): FleetRunValues => ({
  horizon_start: form.fields.horizon_start.value,
  horizon_end: form.fields.horizon_end.value,
  include_recurring: form.fields.include_recurring.value
})

const fleetRun = reactive<FleetRunValues>(
  props.form
    ? valuesFromForm(props.form)
    : {horizon_start: "", horizon_end: "", include_recurring: false}
)

const pendingValidations: FleetRunValues[] = []

const values = (): FleetRunValues => ({
  horizon_start: fleetRun.horizon_start,
  horizon_end: fleetRun.horizon_end,
  include_recurring: fleetRun.include_recurring
})

const sameValues = (left: FleetRunValues, right: FleetRunValues) =>
  left.horizon_start === right.horizon_start &&
  left.horizon_end === right.horizon_end &&
  left.include_recurring === right.include_recurring

watch(
  () => props.form,
  (serverForm) => {
    if (!serverForm) return

    const serverValues = valuesFromForm(serverForm)
    const acknowledgedIndex = pendingValidations.findIndex((sent) =>
      sameValues(sent, serverValues)
    )
    const hasNewerTyping =
      acknowledgedIndex >= 0 && acknowledgedIndex < pendingValidations.length - 1

    if (acknowledgedIndex >= 0) pendingValidations.splice(0, acknowledgedIndex + 1)
    if (!hasNewerTyping) Object.assign(fleetRun, serverValues)
  },
  {deep: true}
)

const validateFleetRun = () => {
  const formValues = values()
  pendingValidations.push(formValues)
  emit("validate-fleet-run", {fleet_run: formValues})
}

const createFleetRun = () => emit("create-fleet-run", {fleet_run: values()})
</script>

<template>
  <section :id="header.id" class="h-full overflow-y-auto bg-base-100">
    <CadencePageHeaderFrame variant="ops">
      <div class="mx-auto max-w-5xl">
        <a
          :id="header.back.id"
          :href="paths.planning"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="inline-flex items-center gap-1 font-mono text-xs text-base-content/55 hover:text-primary"
        >
          <span :class="[header.back.icon, 'h-3.5 w-3.5']"></span>
          {{ header.back.label }}
        </a>
        <h1 class="mt-4 text-2xl font-bold tracking-tight">{{ header.title }}</h1>
        <p class="mt-2 max-w-3xl text-sm text-base-content/60">
          {{ header.copy }}
        </p>
      </div>
    </CadencePageHeaderFrame>

    <div class="mx-auto grid max-w-5xl gap-5 p-5 lg:grid-cols-[minmax(0,1fr)_20rem] lg:p-7">
      <section class="border border-base-300 bg-base-200/15 p-5">
        <form
          v-if="policy_state.active && form"
          :id="form.id"
          class="space-y-5"
          @submit.prevent="createFleetRun"
        >
          <div class="grid gap-4 sm:grid-cols-2">
            <CadenceField
              :control-id="form.fields.horizon_start.id"
              wrapper-class="fieldset mb-3"
              :label="form.fields.horizon_start.label"
              label-class="hud-label block mb-1.5"
            >
              <input
                :id="form.fields.horizon_start.id"
                v-model="fleetRun.horizon_start"
                :name="form.fields.horizon_start.name"
                :type="form.fields.horizon_start.type"
                :required="form.fields.horizon_start.required"
                :class="[
                  'w-full input',
                  form.fields.horizon_start.errors.length > 0 && 'input-error'
                ]"
                @input="validateFleetRun"
              >
              <template #errors>
                <CadenceValidationMessage
                  v-for="error in form.fields.horizon_start.errors"
                  :key="error"
                >{{ error }}</CadenceValidationMessage>
              </template>
            </CadenceField>

            <CadenceField
              :control-id="form.fields.horizon_end.id"
              wrapper-class="fieldset mb-3"
              :label="form.fields.horizon_end.label"
              label-class="hud-label block mb-1.5"
            >
              <input
                :id="form.fields.horizon_end.id"
                v-model="fleetRun.horizon_end"
                :name="form.fields.horizon_end.name"
                :type="form.fields.horizon_end.type"
                :required="form.fields.horizon_end.required"
                :class="[
                  'w-full input',
                  form.fields.horizon_end.errors.length > 0 && 'input-error'
                ]"
                @input="validateFleetRun"
              >
              <template #errors>
                <CadenceValidationMessage
                  v-for="error in form.fields.horizon_end.errors"
                  :key="error"
                >{{ error }}</CadenceValidationMessage>
              </template>
            </CadenceField>
          </div>

          <div class="fieldset mb-3">
            <label class="flex cursor-pointer items-start gap-3">
              <input type="hidden" :name="form.fields.include_recurring.name" value="false">
              <input
                :id="form.fields.include_recurring.id"
                v-model="fleetRun.include_recurring"
                :name="form.fields.include_recurring.name"
                :value="true"
                type="checkbox"
                class="checkbox checkbox-sm mt-0.5"
                @change="validateFleetRun"
              >
              <span>
                <span class="block text-sm font-medium">
                  {{ form.fields.include_recurring.label }}
                </span>
              </span>
            </label>
          </div>

          <div class="border-l-2 border-primary/35 bg-primary/[0.035] px-4 py-3">
            <p class="hud-label">{{ form.snapshot.label }}</p>
            <p class="mt-1 text-sm text-base-content/60">
              {{ form.snapshot.copy }}
            </p>
          </div>

          <button
            :id="form.submit.id"
            type="submit"
            class="btn btn-primary btn-sm w-full font-mono text-xs uppercase tracking-wider"
          >
            {{ form.submit.label }}
          </button>
        </form>

        <div
          v-else-if="policy_state.required"
          :id="policy_state.required.id"
          class="py-10 text-center"
        >
          <span
            :class="[policy_state.required.icon, 'mx-auto h-8 w-8 text-warning/60']"
          ></span>
          <h2 class="mt-4 text-base font-semibold">{{ policy_state.required.title }}</h2>
          <p class="mx-auto mt-2 max-w-lg text-sm text-base-content/55">
            {{ policy_state.required.copy }}
          </p>
          <a
            :id="policy_state.required.action_id"
            :href="paths.policy"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="btn btn-warning btn-sm mt-5"
          >{{ policy_state.required.action_label }}</a>
        </div>
      </section>

      <aside
        v-if="preview"
        :id="preview.id"
        class="border border-base-300 bg-base-200/15"
      >
        <div class="border-b border-base-300 px-4 py-3">
          <p class="hud-label">{{ preview.eyebrow }}</p>
          <p class="mt-1 font-mono text-sm">{{ preview.version }}</p>
        </div>
        <dl class="divide-y divide-base-300 text-xs">
          <div
            v-for="fact in preview.facts"
            :key="fact.term"
            class="flex items-center justify-between gap-3 px-4 py-3"
          >
            <dt class="text-base-content/50">{{ fact.term }}</dt>
            <dd class="font-mono text-base-content/75">{{ fact.value }}</dd>
          </div>
        </dl>
        <CadenceDetailsFrame :id="preview.details.id" class="border-t border-base-300">
          <summary class="cursor-pointer px-4 py-3 text-xs font-semibold">
            {{ preview.details.summary }}
          </summary>
          <p class="border-t border-base-300 px-4 py-3 text-xs leading-relaxed text-base-content/55">
            {{ preview.details.copy }}
          </p>
        </CadenceDetailsFrame>
      </aside>
    </div>
  </section>
</template>
