<script setup lang="ts">
import {reactive, watch} from "vue"

type Breadcrumb = {
  label: string
  href: string | null
}

type ProfilePage = {
  id: string
  title: string
  subtitle: string
  breadcrumbs: Breadcrumb[]
}

type FormSection = {
  id: string
  number: string
  title: string
  description: string | null
}

type FormField = {
  id: string
  name: string
  type: "text" | "number" | "select"
  label: string
  required: boolean
  value: string
}

type ApplicationField = {
  id: string
  name: string
  value: Record<string, string>
}

type ProfileForm = {
  id: string
  sections: {
    identity: FormSection
    protocols: FormSection
    frame_parameters: FormSection
    applications: FormSection
  }
  fields: {
    display_name: FormField
    downlink_protocol: FormField
    uplink_protocol: FormField
    frame_size: FormField
    secondary_header_length: FormField
    insert_zone_length: FormField
    truncated_primary_header: FormField
    ocf_length: FormField
    applications: ApplicationField
  }
  actions: {
    submit: {id: string; label: string}
    cancel: {id: string; label: string; href: string}
  }
}

type SelectOption = {
  label: string
  value: string
}

type ProfileOptions = {
  downlink_protocols: SelectOption[]
  uplink_protocols: SelectOption[]
  truncated_primary_headers: SelectOption[]
  operational_control_fields: SelectOption[]
  frame_fields: {
    secondary_header_length: string[]
    insert_zone_length: string[]
    truncated_primary_header: string[]
  }
}

type ApplicationOption = {
  id: string
  key: string
  name: string
  value: string
  label: string
  description: string
  available: boolean
  availability_label: string | null
}

type ProfileValues = {
  display_name: string
  downlink_protocol: string
  uplink_protocol: string
  frame_size: string
  secondary_header_length: string
  insert_zone_length: string
  truncated_primary_header: string
  ocf_length: string
  applications: Record<string, string>
}

type ProfilePayload = {
  spacecraft_type: ProfileValues
}

const props = defineProps<{
  page: ProfilePage
  form: ProfileForm
  options: ProfileOptions
  applications: ApplicationOption[]
}>()

const emit = defineEmits<{
  validate: [payload: ProfilePayload]
  save: [payload: ProfilePayload]
}>()

const formValues = (form: ProfileForm): ProfileValues => ({
  display_name: form.fields.display_name.value,
  downlink_protocol: form.fields.downlink_protocol.value,
  uplink_protocol: form.fields.uplink_protocol.value,
  frame_size: form.fields.frame_size.value,
  secondary_header_length: form.fields.secondary_header_length.value,
  insert_zone_length: form.fields.insert_zone_length.value,
  truncated_primary_header: form.fields.truncated_primary_header.value,
  ocf_length: form.fields.ocf_length.value,
  applications: {...form.fields.applications.value}
})

const values = reactive<ProfileValues>(formValues(props.form))
const pendingValidations: ProfileValues[] = []
const supersededValidations: ProfileValues[] = []
let acceptedServerValues = formValues(props.form)

const applicationEntries = (applications: Record<string, string>) =>
  Object.entries(applications).sort(([left], [right]) => left.localeCompare(right))

const sameValues = (left: ProfileValues, right: ProfileValues) =>
  left.display_name === right.display_name &&
  left.downlink_protocol === right.downlink_protocol &&
  left.uplink_protocol === right.uplink_protocol &&
  left.frame_size === right.frame_size &&
  left.secondary_header_length === right.secondary_header_length &&
  left.insert_zone_length === right.insert_zone_length &&
  left.truncated_primary_header === right.truncated_primary_header &&
  left.ocf_length === right.ocf_length &&
  JSON.stringify(applicationEntries(left.applications)) ===
    JSON.stringify(applicationEntries(right.applications))

const assignValues = (nextValues: ProfileValues) => {
  Object.assign(values, nextValues, {applications: {...nextValues.applications}})
}

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

      if (!hasNewerTyping && sameValues(profileValues(), serverValues)) {
        assignValues(serverValues)
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

    if (pendingValidations.length === 0 && sameValues(profileValues(), acceptedServerValues)) {
      assignValues(serverValues)
      acceptedServerValues = serverValues
      return
    }

    if (pendingValidations.length === 0 && sameValues(profileValues(), serverValues)) {
      acceptedServerValues = serverValues
    }
  },
  {deep: true}
)

function profileValues(): ProfileValues {
  return {
    display_name: values.display_name,
    downlink_protocol: values.downlink_protocol,
    uplink_protocol: values.uplink_protocol,
    frame_size: values.frame_size,
    secondary_header_length: values.secondary_header_length,
    insert_zone_length: values.insert_zone_length,
    truncated_primary_header: values.truncated_primary_header,
    ocf_length: values.ocf_length,
    applications: {...values.applications}
  }
}

const validate = () => {
  const profile = profileValues()
  pendingValidations.push(profile)
  emit("validate", {spacecraft_type: profile})
}

const applicationSelected = (applicationKey: string) => applicationKey in values.applications

const frameFieldVisible = (field: keyof ProfileOptions["frame_fields"]) =>
  props.options.frame_fields[field].includes(values.downlink_protocol)

const toggleApplication = (applicationKey: string, event: Event) => {
  const input = event.target as HTMLInputElement

  if (input.checked) {
    values.applications[applicationKey] = "1"
  } else {
    delete values.applications[applicationKey]
  }

  validate()
}

const save = () => emit("save", {spacecraft_type: profileValues()})
</script>

<template>
  <div :id="page.id" class="space-y-6 max-w-2xl">
    <header class="border-b border-primary/20 pb-4">
      <div>
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
                class="hover:text-primary transition-colors"
              >{{ breadcrumb.label }}</a>
            </template>
          </nav>
          <h1 class="mt-2 text-2xl font-bold text-base-content tracking-tight">
            {{ page.title }}
          </h1>
          <p class="mt-1 max-w-3xl text-sm text-base-content/70">{{ page.subtitle }}</p>
        </div>
      </div>
    </header>

    <form :id="form.id" class="space-y-8" @submit.prevent="save">
      <section :id="form.sections.identity.id" class="space-y-4">
        <div class="flex items-center gap-3">
          <span class="hud-label text-primary/70">{{ form.sections.identity.number }}</span>
          <h2 class="hud-label">{{ form.sections.identity.title }}</h2>
          <div class="flex-1 h-px bg-base-300/60"></div>
        </div>

        <div class="fieldset mb-3">
          <label :for="form.fields.display_name.id">
            <span class="hud-label block mb-1.5">{{ form.fields.display_name.label }}</span>
            <input
              :id="form.fields.display_name.id"
              v-model="values.display_name"
              :name="form.fields.display_name.name"
              :type="form.fields.display_name.type"
              :required="form.fields.display_name.required"
              class="w-full input"
              @input="validate"
            >
          </label>
        </div>
      </section>

      <section :id="form.sections.protocols.id" class="space-y-4">
        <div class="flex items-center gap-3">
          <span class="hud-label text-primary/70">{{ form.sections.protocols.number }}</span>
          <h2 class="hud-label">{{ form.sections.protocols.title }}</h2>
          <div class="flex-1 h-px bg-base-300/60"></div>
        </div>

        <div class="fieldset mb-3">
          <label :for="form.fields.downlink_protocol.id">
            <span class="hud-label block mb-1.5">
              {{ form.fields.downlink_protocol.label }}
            </span>
            <select
              :id="form.fields.downlink_protocol.id"
              v-model="values.downlink_protocol"
              :name="form.fields.downlink_protocol.name"
              :required="form.fields.downlink_protocol.required"
              class="w-full select"
              @change="validate"
            >
              <option
                v-for="option in options.downlink_protocols"
                :key="option.value"
                :value="option.value"
              >{{ option.label }}</option>
            </select>
          </label>
        </div>

        <div class="fieldset mb-3">
          <label :for="form.fields.uplink_protocol.id">
            <span class="hud-label block mb-1.5">
              {{ form.fields.uplink_protocol.label }}
            </span>
            <select
              :id="form.fields.uplink_protocol.id"
              v-model="values.uplink_protocol"
              :name="form.fields.uplink_protocol.name"
              :required="form.fields.uplink_protocol.required"
              class="w-full select"
              @change="validate"
            >
              <option
                v-for="option in options.uplink_protocols"
                :key="option.value"
                :value="option.value"
              >{{ option.label }}</option>
            </select>
          </label>
        </div>
      </section>

      <section :id="form.sections.frame_parameters.id" class="space-y-4">
        <div class="flex items-center gap-3">
          <span class="hud-label text-primary/70">
            {{ form.sections.frame_parameters.number }}
          </span>
          <h2 class="hud-label">{{ form.sections.frame_parameters.title }}</h2>
          <div class="flex-1 h-px bg-base-300/60"></div>
        </div>

        <p class="text-sm text-base-content/70">
          {{ form.sections.frame_parameters.description }}
        </p>

        <div class="fieldset mb-3">
          <label :for="form.fields.frame_size.id">
            <span class="hud-label block mb-1.5">{{ form.fields.frame_size.label }}</span>
            <input
              :id="form.fields.frame_size.id"
              v-model="values.frame_size"
              :name="form.fields.frame_size.name"
              :type="form.fields.frame_size.type"
              :required="form.fields.frame_size.required"
              class="w-full input"
              @input="validate"
            >
          </label>
        </div>

        <div v-if="frameFieldVisible('secondary_header_length')" class="fieldset mb-3">
          <label :for="form.fields.secondary_header_length.id">
            <span class="hud-label block mb-1.5">
              {{ form.fields.secondary_header_length.label }}
            </span>
            <input
              :id="form.fields.secondary_header_length.id"
              v-model="values.secondary_header_length"
              :name="form.fields.secondary_header_length.name"
              :type="form.fields.secondary_header_length.type"
              :required="form.fields.secondary_header_length.required"
              class="w-full input"
              @input="validate"
            >
          </label>
        </div>

        <div v-if="frameFieldVisible('insert_zone_length')" class="fieldset mb-3">
          <label :for="form.fields.insert_zone_length.id">
            <span class="hud-label block mb-1.5">
              {{ form.fields.insert_zone_length.label }}
            </span>
            <input
              :id="form.fields.insert_zone_length.id"
              v-model="values.insert_zone_length"
              :name="form.fields.insert_zone_length.name"
              :type="form.fields.insert_zone_length.type"
              :required="form.fields.insert_zone_length.required"
              class="w-full input"
              @input="validate"
            >
          </label>
        </div>

        <div v-if="frameFieldVisible('truncated_primary_header')" class="fieldset mb-3">
          <label :for="form.fields.truncated_primary_header.id">
            <span class="hud-label block mb-1.5">
              {{ form.fields.truncated_primary_header.label }}
            </span>
            <select
              :id="form.fields.truncated_primary_header.id"
              v-model="values.truncated_primary_header"
              :name="form.fields.truncated_primary_header.name"
              :required="form.fields.truncated_primary_header.required"
              class="w-full select"
              @change="validate"
            >
              <option
                v-for="option in options.truncated_primary_headers"
                :key="option.value"
                :value="option.value"
              >{{ option.label }}</option>
            </select>
          </label>
        </div>

        <div class="fieldset mb-3">
          <label :for="form.fields.ocf_length.id">
            <span class="hud-label block mb-1.5">{{ form.fields.ocf_length.label }}</span>
            <select
              :id="form.fields.ocf_length.id"
              v-model="values.ocf_length"
              :name="form.fields.ocf_length.name"
              :required="form.fields.ocf_length.required"
              class="w-full select"
              @change="validate"
            >
              <option
                v-for="option in options.operational_control_fields"
                :key="option.value"
                :value="option.value"
              >{{ option.label }}</option>
            </select>
          </label>
        </div>
      </section>

      <section :id="form.sections.applications.id" class="space-y-4">
        <div class="flex items-center gap-3">
          <span class="hud-label text-primary/70">{{ form.sections.applications.number }}</span>
          <h2 class="hud-label">{{ form.sections.applications.title }}</h2>
          <div class="flex-1 h-px bg-base-300/60"></div>
        </div>

        <p class="text-sm text-base-content/70">
          {{ form.sections.applications.description }}
        </p>

        <div :id="form.fields.applications.id" class="space-y-3">
          <label
            v-for="application in applications"
            :key="application.key"
            :class="[
              'flex items-start gap-3 rounded border p-3 transition-colors',
              application.available
                ? 'border-base-300 bg-base-100/40 border-l-2 border-l-primary/40 hover:border-l-primary cursor-pointer'
                : 'border-base-300/50 bg-base-100/20 opacity-50 cursor-not-allowed'
            ]"
          >
            <input
              :id="application.id"
              type="checkbox"
              :name="application.name"
              :value="application.value"
              :checked="applicationSelected(application.key)"
              :disabled="!application.available"
              class="checkbox checkbox-primary mt-0.5"
              @change="toggleApplication(application.key, $event)"
            >
            <div>
              <div class="font-medium text-base-content">
                {{ application.label }}
                <span v-if="application.availability_label" class="hud-label ml-2">
                  {{ application.availability_label }}
                </span>
              </div>
              <p class="mt-0.5 text-sm text-base-content/70">{{ application.description }}</p>
            </div>
          </label>
        </div>
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
