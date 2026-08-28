<script setup lang="ts">
import {reactive, watch} from "vue"
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"
import CadenceField from "./ui/components/CadenceField.vue"
import CadenceFormActions from "./ui/components/CadenceFormActions.vue"
import CadenceFormSectionHeader from "./ui/components/CadenceFormSectionHeader.vue"

type Breadcrumb = {
  label: string
  href: string | null
}

type Page = {
  id: string
  heading: string
  subtitle: string
  breadcrumbs: Breadcrumb[]
}

type Option = {
  label: string
  value: string
  disabled: boolean
}

type BackendPresentation = {
  label: string
  placeholder: string
}

type Visibility = {
  field: string
  equals: string
} | null

type Reference = {
  provider_id: string
  version: number
  mode: string
  result_limit: number
} | null

type Field = {
  key: string
  id: string
  name: string
  type: "hidden" | "text" | "textarea" | "number" | "url" | "select"
  label: string | null
  required: boolean
  placeholder: string | null
  min: number | null
  max: number | null
  step: string | null
  options: Option[]
  presentations?: Record<string, BackendPresentation>
  value: string
  wrapper_id?: string
  help?: string | null
  default?: string
  reference?: Reference
  visible_when?: Visibility
}

type Section = {
  id: string
  number: string
  title: string
  field_keys: string[]
}

type ConfigurationSection = {
  id: string
  fields_id: string
  number: string
  title: string
  description: string | null
  fields: Field[]
}

type Connector = {
  options: Option[]
  selected: {
    id: string
    form_value: string
    provider_type: string
    client_key: string
    label: string
    description: string
  }
  configuration: {
    id: string
    kind: string
    description: string | null
    sections: ConfigurationSection[]
  }
  boundary: {id: string; text: string}
}

type ProviderAccountForm = {
  id: string
  hidden_field_keys: string[]
  sections: {
    network_identity: Section
    credential_registry: Section
    organization_guardrails: Section
  }
  fields: Record<string, Field>
  connector: Connector
  credential_note: {id: string; text: string}
  actions: {
    submit: {id: string; label: string}
    cancel: {id: string; label: string; href: string}
  }
}

type ProviderAccountValues = Record<string, string>
type ProviderAccountPayload = {provider_account: ProviderAccountValues}

const props = defineProps<{
  page: Page
  form: ProviderAccountForm
}>()

const emit = defineEmits<{
  validate: [payload: ProviderAccountPayload]
  save: [payload: ProviderAccountPayload]
}>()

const allFields = (form: ProviderAccountForm): Field[] => [
  ...Object.values(form.fields),
  ...form.connector.configuration.sections.flatMap((section) => section.fields)
]

const formValues = (form: ProviderAccountForm): ProviderAccountValues =>
  Object.fromEntries(allFields(form).map((field) => [field.key, field.value]))

const providerAccount = reactive<ProviderAccountValues>(formValues(props.form))
const pendingValidations: ProviderAccountValues[] = []

const values = (): ProviderAccountValues => ({...providerAccount})

const acknowledges = (sent: ProviderAccountValues, server: ProviderAccountValues) =>
  Object.entries(sent).every(([key, value]) => !(key in server) || server[key] === value)

const replaceValues = (serverValues: ProviderAccountValues) => {
  for (const key of Object.keys(providerAccount)) {
    if (!(key in serverValues)) delete providerAccount[key]
  }

  Object.assign(providerAccount, serverValues)
}

const optionIncludes = (options: Option[], value: string | undefined) =>
  options.some((option) => option.value === value && !option.disabled)

watch(
  () => props.form,
  (serverForm) => {
    const serverValues = formValues(serverForm)
    const acknowledgedIndex = pendingValidations.findIndex((sent) =>
      acknowledges(sent, serverValues)
    )
    const latestPending = pendingValidations[pendingValidations.length - 1]
    const hasNewerTyping =
      acknowledgedIndex >= 0
        ? acknowledgedIndex < pendingValidations.length - 1
        : latestPending !== undefined && !acknowledges(latestPending, serverValues)
    const serverCorrectedSelection =
      (latestPending !== undefined &&
        !optionIncludes(serverForm.connector.options, latestPending.provider_type)) ||
      (latestPending !== undefined &&
        !optionIncludes(serverForm.fields.backend_type.options, latestPending.backend_type))

    if (acknowledgedIndex >= 0) pendingValidations.splice(0, acknowledgedIndex + 1)

    if (!hasNewerTyping || serverCorrectedSelection) {
      if (serverCorrectedSelection) pendingValidations.splice(0)
      replaceValues(serverValues)
    }
  },
  {deep: true}
)

const fieldsFor = (section: Section) =>
  section.field_keys.map((key) => props.form.fields[key]).filter((field) => field !== undefined)

const visible = (field: Field) =>
  field.visible_when === undefined ||
  field.visible_when === null ||
  (providerAccount[field.visible_when.field] ?? "") === field.visible_when.equals

const presentation = (field: Field): BackendPresentation | undefined =>
  field.presentations?.[providerAccount.backend_type ?? ""]

const fieldLabel = (field: Field) => presentation(field)?.label ?? field.label
const fieldPlaceholder = (field: Field) => presentation(field)?.placeholder ?? field.placeholder

const validate = () => {
  const currentValues = values()
  pendingValidations.push(currentValues)
  emit("validate", {provider_account: currentValues})
}

const save = () => emit("save", {provider_account: values()})
</script>

<template>
  <div :id="page.id" class="max-w-3xl space-y-6">
    <CadencePageHeaderFrame variant="compact">
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
          {{ page.heading }}
        </h1>
        <p class="mt-1 max-w-3xl text-sm text-base-content/70">{{ page.subtitle }}</p>
      </div>
    </CadencePageHeaderFrame>

    <form :id="form.id" class="space-y-8" @submit.prevent="save">
      <input
        v-for="fieldKey in form.hidden_field_keys"
        :id="form.fields[fieldKey].id"
        :key="fieldKey"
        :name="form.fields[fieldKey].name"
        type="hidden"
        :value="providerAccount[fieldKey]"
      >

      <section :id="form.sections.network_identity.id" class="space-y-4">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.network_identity.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.network_identity.title"
          title-class="hud-label"
          divider-class="h-px flex-1 bg-base-300/60"
        />

        <CadenceField
          v-for="field in fieldsFor(form.sections.network_identity)"
          :key="field.key"
          :control-id="field.id"
          wrapper-class="fieldset mb-3"
          :label="fieldLabel(field)"
          label-class="hud-label mb-1.5 block"
        >
          <select
            v-if="field.type === 'select'"
            :id="field.id"
            v-model="providerAccount[field.key]"
            :name="field.name"
            :required="field.required"
            class="select w-full"
            @change="validate"
          >
            <option
              v-for="option in field.options"
              :key="`${option.value}-${option.label}`"
              :value="option.value"
              :disabled="option.disabled"
            >{{ option.label }}</option>
          </select>
          <input
            v-else
            :id="field.id"
            v-model="providerAccount[field.key]"
            :name="field.name"
            :type="field.type"
            :placeholder="fieldPlaceholder(field)"
            :required="field.required"
            :min="field.min"
            :max="field.max"
            :step="field.step"
            class="input w-full"
            @input="validate"
          >
        </CadenceField>

        <div
          :id="form.connector.selected.id"
          :data-provider-type="form.connector.selected.form_value"
          :data-provider-client="form.connector.selected.client_key"
          class="grid grid-cols-[0.3rem_minmax(0,1fr)_auto] gap-4 border-y border-base-300/70 bg-base-200/45 px-4 py-3"
        >
          <span class="rounded-full bg-info"></span>
          <div>
            <p class="hud-label">Compiled Provider Connector</p>
            <p class="mt-1 font-medium">{{ form.connector.selected.label }}</p>
            <p class="mt-1 text-xs text-base-content/60">
              {{ form.connector.selected.description }}
            </p>
          </div>
          <span
            class="self-start font-mono text-[0.65rem] uppercase tracking-[0.12em] text-base-content/45"
          >{{ form.connector.selected.client_key }}</span>
        </div>

        <div
          :id="form.connector.boundary.id"
          class="border-l-2 border-info/60 bg-info/10 px-4 py-3 text-sm text-base-content/70"
        >
          {{ form.connector.boundary.text }}
        </div>
      </section>

      <div
        :id="form.connector.configuration.id"
        :data-extension-presentation="form.connector.configuration.kind"
        class="space-y-8"
      >
        <p
          v-if="form.connector.configuration.description"
          class="text-sm text-base-content/65"
        >
          {{ form.connector.configuration.description }}
        </p>

        <section
          v-for="section in form.connector.configuration.sections"
          :id="section.id"
          :key="section.id"
          class="space-y-4"
        >
          <CadenceFormSectionHeader
            wrapper-class="flex items-center gap-3"
            :number="section.number"
            number-class="hud-label text-primary/70"
            :title="section.title"
            title-class="hud-label"
            divider-class="h-px flex-1 bg-base-300/60"
          />

          <p v-if="section.description" class="text-sm text-base-content/65">
            {{ section.description }}
          </p>

          <div :id="section.fields_id" class="grid gap-x-4 sm:grid-cols-2">
            <template v-for="field in section.fields" :key="field.key">
              <CadenceField
                v-if="visible(field)"
                :id="field.wrapper_id"
                :control-id="field.id"
                wrapper-class="fieldset mb-3"
                :label="fieldLabel(field)"
                label-class="hud-label mb-1.5 block"
              >
                <select
                  v-if="field.type === 'select'"
                  :id="field.id"
                  v-model="providerAccount[field.key]"
                  :name="field.name"
                  :required="field.required"
                  class="select w-full"
                  @change="validate"
                >
                  <option
                    v-for="option in field.options"
                    :key="`${option.value}-${option.label}`"
                    :value="option.value"
                    :disabled="option.disabled"
                  >{{ option.label }}</option>
                </select>
                <textarea
                  v-else-if="field.type === 'textarea'"
                  :id="field.id"
                  v-model="providerAccount[field.key]"
                  :name="field.name"
                  :placeholder="fieldPlaceholder(field)"
                  :required="field.required"
                  class="textarea w-full"
                  @input="validate"
                ></textarea>
                <input
                  v-else
                  :id="field.id"
                  v-model="providerAccount[field.key]"
                  :name="field.name"
                  :type="field.type"
                  :placeholder="fieldPlaceholder(field)"
                  :required="field.required"
                  :min="field.min"
                  :max="field.max"
                  :step="field.step"
                  class="input w-full"
                  @input="validate"
                >
                <template #help>
                  <p v-if="field.help" class="-mt-1 mb-3 text-xs text-base-content/55">
                    {{ field.help }}
                  </p>
                </template>
              </CadenceField>
            </template>
          </div>
        </section>
      </div>

      <section :id="form.sections.credential_registry.id" class="space-y-4">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.credential_registry.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.credential_registry.title"
          title-class="hud-label"
          divider-class="h-px flex-1 bg-base-300/60"
        />

        <CadenceField
          v-for="field in fieldsFor(form.sections.credential_registry)"
          :key="field.key"
          :control-id="field.id"
          wrapper-class="fieldset mb-3"
          :label="fieldLabel(field)"
          label-class="hud-label mb-1.5 block"
        >
          <select
            v-if="field.type === 'select'"
            :id="field.id"
            v-model="providerAccount[field.key]"
            :name="field.name"
            :required="field.required"
            class="select w-full"
            @change="validate"
          >
            <option
              v-for="option in field.options"
              :key="`${option.value}-${option.label}`"
              :value="option.value"
              :disabled="option.disabled"
            >{{ option.label }}</option>
          </select>
          <input
            v-else
            :id="field.id"
            v-model="providerAccount[field.key]"
            :name="field.name"
            :type="field.type"
            :placeholder="fieldPlaceholder(field)"
            :required="field.required"
            :min="field.min"
            :max="field.max"
            :step="field.step"
            class="input w-full"
            @input="validate"
          >
        </CadenceField>

        <p :id="form.credential_note.id" class="text-xs text-base-content/60">
          {{ form.credential_note.text }}
        </p>
      </section>

      <section :id="form.sections.organization_guardrails.id" class="space-y-4">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.organization_guardrails.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.organization_guardrails.title"
          title-class="hud-label"
          divider-class="h-px flex-1 bg-base-300/60"
        />

        <CadenceField
          v-for="field in fieldsFor(form.sections.organization_guardrails)"
          :key="field.key"
          :control-id="field.id"
          wrapper-class="fieldset mb-3"
          :label="fieldLabel(field)"
          label-class="hud-label mb-1.5 block"
        >
          <input
            :id="field.id"
            v-model="providerAccount[field.key]"
            :name="field.name"
            :type="field.type"
            :placeholder="fieldPlaceholder(field)"
            :required="field.required"
            :min="field.min"
            :max="field.max"
            :step="field.step"
            class="input w-full"
            @input="validate"
          >
        </CadenceField>
      </section>

      <CadenceFormActions wrapper-class="flex items-center gap-3 border-t border-base-300/60 pt-5">
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
      </CadenceFormActions>
    </form>
  </div>
</template>
