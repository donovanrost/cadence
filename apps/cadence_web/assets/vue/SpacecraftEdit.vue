<script setup lang="ts">
import {reactive, watch} from "vue"
import CadenceFormActions from "./ui/components/CadenceFormActions.vue"
import CadenceFormSectionHeader from "./ui/components/CadenceFormSectionHeader.vue"

type Breadcrumb = {
  id: string
  label: string
  href: string | null
}

type SpacecraftPage = {
  id: string
  heading: string
  subtitle: string
  breadcrumbs: Breadcrumb[]
}

type Section = {
  id: string
  number: string
  title: string
}

type TextField = {
  id: string
  name: string
  type: "text"
  label: string
  required: boolean
  value: string
}

type SelectField = {
  id: string
  name: string
  type: "select"
  label: string
  required: boolean
  value: string
}

type SpacecraftForm = {
  id: string
  sections: {
    identity: Section
    profile: Section
  }
  fields: {
    display_name: TextField
    scid: TextField
    spacecraft_type_id: SelectField
  }
  actions: {
    submit: {id: string; label: string}
    cancel: {id: string; label: string; href: string}
  }
}

type ProfileOptions = {
  options: {label: string; value: string}[]
}

type SpacecraftValues = {
  display_name: string
  scid: string
  spacecraft_type_id: string
}

type SpacecraftPayload = {
  spacecraft: SpacecraftValues
}

const props = defineProps<{
  page: SpacecraftPage
  form: SpacecraftForm
  profile_options: ProfileOptions
}>()

const emit = defineEmits<{
  validate: [payload: SpacecraftPayload]
  save: [payload: SpacecraftPayload]
}>()

const formValues = (form: SpacecraftForm): SpacecraftValues => ({
  display_name: form.fields.display_name.value,
  scid: form.fields.scid.value,
  spacecraft_type_id: form.fields.spacecraft_type_id.value
})

const spacecraft = reactive<SpacecraftValues>(formValues(props.form))
const pendingValidations: SpacecraftValues[] = []

const values = (): SpacecraftValues => ({
  display_name: spacecraft.display_name,
  scid: spacecraft.scid,
  spacecraft_type_id: spacecraft.spacecraft_type_id
})

const sameValues = (left: SpacecraftValues, right: SpacecraftValues) =>
  left.display_name === right.display_name &&
  left.scid === right.scid &&
  left.spacecraft_type_id === right.spacecraft_type_id

watch(
  () => props.form,
  (serverForm) => {
    const serverValues = formValues(serverForm)
    const acknowledgedIndex = pendingValidations.findIndex((sent) =>
      sameValues(sent, serverValues)
    )
    const hasNewerTyping =
      pendingValidations.length > 0 &&
      (acknowledgedIndex < 0 || acknowledgedIndex < pendingValidations.length - 1)

    if (acknowledgedIndex >= 0) pendingValidations.splice(0, acknowledgedIndex + 1)

    if (!hasNewerTyping) Object.assign(spacecraft, serverValues)
  },
  {deep: true}
)

const validate = () => {
  const currentValues = values()
  pendingValidations.push(currentValues)
  emit("validate", {spacecraft: currentValues})
}

const save = () => emit("save", {spacecraft: values()})
</script>

<template>
  <div :id="page.id" class="space-y-6 max-w-xl">
    <header class="border-b border-primary/20 pb-4">
      <div>
        <div>
          <nav
            aria-label="Breadcrumb"
            class="flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
          >
            <template
              v-for="(breadcrumb, index) in page.breadcrumbs"
              :key="breadcrumb.id"
            >
              <span v-if="index > 0" class="text-base-content/20" aria-hidden="true">/</span>
              <span
                v-if="breadcrumb.href === null"
                :id="breadcrumb.id"
                class="text-primary/90"
              >
                {{ breadcrumb.label }}
              </span>
              <a
                v-else
                :id="breadcrumb.id"
                :href="breadcrumb.href"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="hover:text-primary transition-colors"
              >{{ breadcrumb.label }}</a>
            </template>
          </nav>
          <h1 class="mt-2 text-2xl font-bold text-base-content tracking-tight">
            {{ page.heading }}
          </h1>
          <p class="mt-1 max-w-3xl text-sm text-base-content/70">{{ page.subtitle }}</p>
        </div>
      </div>
    </header>

    <form :id="form.id" class="space-y-8" @submit.prevent="save">
      <section :id="form.sections.identity.id" class="space-y-4">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.identity.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.identity.title"
          title-class="hud-label"
          divider-class="flex-1 h-px bg-base-300/60"
        />

        <div class="fieldset mb-3">
          <label :for="form.fields.display_name.id">
            <span class="hud-label block mb-1.5">{{ form.fields.display_name.label }}</span>
            <input
              :id="form.fields.display_name.id"
              v-model="spacecraft.display_name"
              :name="form.fields.display_name.name"
              :type="form.fields.display_name.type"
              :required="form.fields.display_name.required"
              class="w-full input"
              @input="validate"
            >
          </label>
        </div>

        <div class="fieldset mb-3">
          <label :for="form.fields.scid.id">
            <span class="hud-label block mb-1.5">{{ form.fields.scid.label }}</span>
            <input
              :id="form.fields.scid.id"
              v-model="spacecraft.scid"
              :name="form.fields.scid.name"
              :type="form.fields.scid.type"
              :required="form.fields.scid.required"
              class="w-full input"
              @input="validate"
            >
          </label>
        </div>
      </section>

      <section :id="form.sections.profile.id" class="space-y-4">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.profile.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.profile.title"
          title-class="hud-label"
          divider-class="flex-1 h-px bg-base-300/60"
        />

        <div class="fieldset mb-3">
          <label :for="form.fields.spacecraft_type_id.id">
            <span class="hud-label block mb-1.5">
              {{ form.fields.spacecraft_type_id.label }}
            </span>
            <select
              :id="form.fields.spacecraft_type_id.id"
              v-model="spacecraft.spacecraft_type_id"
              :name="form.fields.spacecraft_type_id.name"
              :required="form.fields.spacecraft_type_id.required"
              class="w-full select"
              @change="validate"
            >
              <option
                v-for="option in profile_options.options"
                :key="`${option.value}-${option.label}`"
                :value="option.value"
              >{{ option.label }}</option>
            </select>
          </label>
        </div>
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
