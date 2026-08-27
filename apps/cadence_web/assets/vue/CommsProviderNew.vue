<script setup lang="ts">
import {reactive, watch} from "vue"
import CadenceField from "./ui/components/CadenceField.vue"

type Breadcrumb = {
  label: string
  href: string | null
}

type Page = {
  id: string
  title: string
  subtitle: string
  breadcrumbs: Breadcrumb[]
}

type Option = {
  label: string
  value: string
}

type AccountSummary = {
  id: string
  ownership_label: string
  display_name: string
  version_label: string
  badge: {status: "ready"; label: string}
  restrictions: {label: string; summary: string}[]
}

type Accounts = {
  empty: boolean
  options: Option[]
  selected: AccountSummary | null
  empty_state: {
    id: string
    heading: string
    message: string
    action: {id: string; label: string; href: string}
  }
}

type Notes = {
  secret_boundary: {id: string; text: string}
  resource_boundary: {id: string; text: string}
}

type Section = {
  id: string
  number: string
  title: string
  field_keys: ProviderFieldKey[]
}

type Field = {
  key: ProviderFieldKey
  id: string
  name: string
  type: "text" | "number" | "select"
  label: string
  required: boolean
  placeholder: string | null
  min: number | null
  options: Option[]
  value: string
}

type Visibility = {
  field: ProviderFieldKey
  equals: string
}

type ProviderForm = {
  id: string
  sections: {
    binding: Section
    resource_scope: Section
    delivery_policy: Section
  }
  fields: Record<ProviderFieldKey, Field>
  conditional: {
    approval_guidance: {
      id: string
      active: boolean
      visible_when: Visibility
      text: string
    }
    bounded_policy: {
      id: string
      active: boolean
      visible_when: Visibility
      field_keys: ProviderFieldKey[]
    }
  }
  actions: {
    submit: {id: string; label: string}
    cancel: {id: string; label: string; href: string}
  }
}

const providerFieldKeys = [
  "display_name",
  "provider_account_grant_id",
  "permitted_resource_refs",
  "policy_mode",
  "maximum_earlier_start_shift_seconds",
  "maximum_later_start_shift_seconds",
  "maximum_earlier_end_shift_seconds",
  "maximum_later_end_shift_seconds",
  "minimum_retained_duration_seconds",
  "approved_station_substitutions",
  "deadline_behavior"
] as const

type ProviderFieldKey = (typeof providerFieldKeys)[number]
type ProviderValues = Record<ProviderFieldKey, string>
type ProviderPayload = {provider: ProviderValues}

const props = defineProps<{
  page: Page
  accounts: Accounts
  notes: Notes
  form: ProviderForm
}>()

const emit = defineEmits<{
  validate: [payload: ProviderPayload]
  save: [payload: ProviderPayload]
}>()

const formValues = (form: ProviderForm): ProviderValues =>
  Object.fromEntries(
    providerFieldKeys.map((key) => [key, form.fields[key].value])
  ) as ProviderValues

const provider = reactive<ProviderValues>(formValues(props.form))
const pendingValidations: ProviderValues[] = []
const supersededValidations: ProviderValues[] = []
let acceptedServerValues = formValues(props.form)

const values = (): ProviderValues => ({...provider})

const sameValues = (left: ProviderValues, right: ProviderValues) =>
  providerFieldKeys.every((key) => left[key] === right[key])

watch(
  () => props.form,
  (serverForm) => {
    const serverValues = formValues(serverForm)
    const acknowledgedIndex = pendingValidations.findIndex((sent) =>
      sameValues(sent, serverValues)
    )

    if (acknowledgedIndex >= 0) {
      supersededValidations.push(...pendingValidations.slice(0, acknowledgedIndex))

      const hasNewerTyping = acknowledgedIndex < pendingValidations.length - 1
      pendingValidations.splice(0, acknowledgedIndex + 1)
      acceptedServerValues = serverValues

      if (!hasNewerTyping && sameValues(provider, serverValues)) {
        Object.assign(provider, serverValues)
      }

      return
    }

    const supersededIndex = supersededValidations.findIndex((sent) =>
      sameValues(sent, serverValues)
    )

    if (supersededIndex >= 0) {
      supersededValidations.splice(supersededIndex, 1)
      return
    }

    if (sameValues(serverValues, acceptedServerValues)) return

    if (pendingValidations.length === 0 && sameValues(provider, acceptedServerValues)) {
      Object.assign(provider, serverValues)
      acceptedServerValues = serverValues
    }
  },
  {deep: true}
)

const fieldsFor = (section: Section) =>
  section.field_keys.map((key) => props.form.fields[key])

const fieldsForKeys = (keys: ProviderFieldKey[]) =>
  keys.map((key) => props.form.fields[key])

const visible = (visibility: Visibility) =>
  provider[visibility.field] === visibility.equals

const validate = () => {
  const currentValues = values()
  pendingValidations.push(currentValues)
  emit("validate", {provider: currentValues})
}

const save = () => emit("save", {provider: values()})
</script>

<template>
  <div :id="page.id" class="max-w-3xl space-y-6">
    <header class="border-b border-primary/20 pb-4">
      <div>
        <nav
          aria-label="Breadcrumb"
          class="flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
        >
          <template
            v-for="(breadcrumb, index) in page.breadcrumbs"
            :key="`${index}-${breadcrumb.label}`"
          >
            <span v-if="index > 0" class="text-base-content/20" aria-hidden="true">/</span>
            <span v-if="breadcrumb.href === null" class="text-primary/90">
              {{ breadcrumb.label }}
            </span>
            <a
              v-else
              :href="breadcrumb.href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="transition-colors hover:text-primary"
            >{{ breadcrumb.label }}</a>
          </template>
        </nav>
        <h1 class="mt-2 text-2xl font-bold tracking-tight text-base-content">
          {{ page.title }}
        </h1>
        <p class="mt-1 max-w-3xl text-sm text-base-content/70">{{ page.subtitle }}</p>
      </div>
    </header>

    <div
      v-if="accounts.empty"
      :id="accounts.empty_state.id"
      class="border border-warning/40 bg-warning/10 p-5"
    >
      <p class="font-semibold">{{ accounts.empty_state.heading }}</p>
      <p class="mt-1 text-sm text-base-content/70">{{ accounts.empty_state.message }}</p>
      <a
        :id="accounts.empty_state.action.id"
        :href="accounts.empty_state.action.href"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="btn btn-secondary btn-sm mt-4"
      >{{ accounts.empty_state.action.label }}</a>
    </div>

    <form v-else :id="form.id" class="space-y-8" @submit.prevent="save">
      <section :id="form.sections.binding.id" class="space-y-4">
        <div class="flex items-center gap-3">
          <span class="hud-label text-primary/70">{{ form.sections.binding.number }}</span>
          <h2 class="hud-label">{{ form.sections.binding.title }}</h2>
          <div class="flex-1 h-px bg-base-300/60"></div>
        </div>

        <CadenceField
          v-for="field in fieldsFor(form.sections.binding)"
          :key="field.key"
          :control-id="field.id"
          wrapper-class="fieldset mb-3"
          :label="field.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            v-if="field.type === 'select'"
            :id="field.id"
            v-model="provider[field.key]"
            :name="field.name"
            :required="field.required"
            class="w-full select"
            @change="validate"
          >
            <option
              v-for="option in field.options"
              :key="`${option.value}-${option.label}`"
              :value="option.value"
            >{{ option.label }}</option>
          </select>
          <input
            v-else
            :id="field.id"
            v-model="provider[field.key]"
            :name="field.name"
            :type="field.type"
            :required="field.required"
            :placeholder="field.placeholder"
            :min="field.min"
            class="w-full input"
            @input="validate"
          >
        </CadenceField>

        <div
          v-if="accounts.selected"
          :id="accounts.selected.id"
          class="border border-base-300 bg-base-200/60 p-4"
        >
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="hud-label">{{ accounts.selected.ownership_label }}</p>
              <p class="mt-1 font-medium">{{ accounts.selected.display_name }}</p>
              <p class="mt-1 font-mono text-xs text-base-content/50">
                {{ accounts.selected.version_label }}
              </p>
            </div>
            <span
              class="inline-flex rounded-full bg-success/20 px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide text-success"
            >{{ accounts.selected.badge.label }}</span>
          </div>
          <div class="mt-4 grid gap-3 sm:grid-cols-2">
            <div
              v-for="restriction in accounts.selected.restrictions"
              :key="restriction.label"
            >
              <p class="hud-label">{{ restriction.label }}</p>
              <p class="mt-1 text-xs text-base-content/70">{{ restriction.summary }}</p>
            </div>
          </div>
          <p
            :id="notes.secret_boundary.id"
            class="mt-4 text-xs text-base-content/60"
          >
            {{ notes.secret_boundary.text }}
          </p>
        </div>
      </section>

      <section :id="form.sections.resource_scope.id" class="space-y-4">
        <div class="flex items-center gap-3">
          <span class="hud-label text-primary/70">
            {{ form.sections.resource_scope.number }}
          </span>
          <h2 class="hud-label">{{ form.sections.resource_scope.title }}</h2>
          <div class="flex-1 h-px bg-base-300/60"></div>
        </div>

        <CadenceField
          v-for="field in fieldsFor(form.sections.resource_scope)"
          :key="field.key"
          :control-id="field.id"
          wrapper-class="fieldset mb-3"
          :label="field.label"
          label-class="hud-label block mb-1.5"
        >
          <input
            :id="field.id"
            v-model="provider[field.key]"
            :name="field.name"
            :type="field.type"
            :required="field.required"
            :placeholder="field.placeholder"
            :min="field.min"
            class="w-full input"
            @input="validate"
          >
        </CadenceField>
        <p :id="notes.resource_boundary.id" class="text-xs text-base-content/60">
          {{ notes.resource_boundary.text }}
        </p>
      </section>

      <section :id="form.sections.delivery_policy.id" class="space-y-4">
        <div class="flex items-center gap-3">
          <span class="hud-label text-primary/70">
            {{ form.sections.delivery_policy.number }}
          </span>
          <h2 class="hud-label">{{ form.sections.delivery_policy.title }}</h2>
          <div class="flex-1 h-px bg-base-300/60"></div>
        </div>

        <CadenceField
          :control-id="form.fields.policy_mode.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.policy_mode.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="form.fields.policy_mode.id"
            v-model="provider.policy_mode"
            :name="form.fields.policy_mode.name"
            :required="form.fields.policy_mode.required"
            class="w-full select"
            @change="validate"
          >
            <option
              v-for="option in form.fields.policy_mode.options"
              :key="option.value"
              :value="option.value"
            >{{ option.label }}</option>
          </select>
        </CadenceField>

        <div
          v-if="visible(form.conditional.approval_guidance.visible_when)"
          :id="form.conditional.approval_guidance.id"
          class="border-l-2 border-info/60 bg-info/10 px-4 py-3 text-sm text-base-content/70"
        >
          {{ form.conditional.approval_guidance.text }}
        </div>

        <div
          v-if="visible(form.conditional.bounded_policy.visible_when)"
          :id="form.conditional.bounded_policy.id"
          class="grid gap-4 sm:grid-cols-2"
        >
          <CadenceField
            v-for="field in fieldsForKeys(form.conditional.bounded_policy.field_keys)"
            :key="field.key"
            :control-id="field.id"
            wrapper-class="fieldset mb-3"
            :label="field.label"
            label-class="hud-label block mb-1.5"
          >
            <input
              :id="field.id"
              v-model="provider[field.key]"
              :name="field.name"
              :type="field.type"
              :required="field.required"
              :placeholder="field.placeholder"
              :min="field.min"
              class="w-full input"
              @input="validate"
            >
          </CadenceField>
        </div>

        <CadenceField
          :control-id="form.fields.deadline_behavior.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.deadline_behavior.label"
          label-class="hud-label block mb-1.5"
        >
          <select
            :id="form.fields.deadline_behavior.id"
            v-model="provider.deadline_behavior"
            :name="form.fields.deadline_behavior.name"
            :required="form.fields.deadline_behavior.required"
            class="w-full select"
            @change="validate"
          >
            <option
              v-for="option in form.fields.deadline_behavior.options"
              :key="option.value"
              :value="option.value"
            >{{ option.label }}</option>
          </select>
        </CadenceField>
      </section>

      <div class="flex items-center gap-3 border-t border-base-300/60 pt-5">
        <button :id="form.actions.submit.id" type="submit" class="btn btn-primary">
          {{ form.actions.submit.label }}
        </button>
        <a
          :id="form.actions.cancel.id"
          :href="form.actions.cancel.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-ghost"
        >{{ form.actions.cancel.label }}</a>
      </div>
    </form>
  </div>
</template>
