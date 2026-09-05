<script setup lang="ts">
import {reactive, watch} from "vue"
import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"
import CadenceField from "./ui/components/CadenceField.vue"
import CadenceFormActions from "./ui/components/CadenceFormActions.vue"
import CadenceNarrowFormPageFrame from "./ui/components/CadenceNarrowFormPageFrame.vue"
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"
import CadencePageTitle from "./ui/components/CadencePageTitle.vue"
import CadenceFormSectionHeader from "./ui/components/CadenceFormSectionHeader.vue"
import CadenceFormSectionFrame from "./ui/components/CadenceFormSectionFrame.vue"

type Breadcrumb = {
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
  empty: boolean
  empty_state: {
    message: string
    action: {id: string; label: string; href: string}
    suffix: string
  }
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
  <CadenceNarrowFormPageFrame :id="page.id">
    <CadencePageHeaderFrame variant="compact">
      <div>
        <div>
          <CadenceBreadcrumbs>
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
          </CadenceBreadcrumbs>
          <CadencePageTitle>
            {{ page.heading }}
          </CadencePageTitle>
          <p class="mt-1 max-w-3xl text-sm text-base-content/70">{{ page.subtitle }}</p>
        </div>
      </div>
    </CadencePageHeaderFrame>

    <form :id="form.id" class="space-y-8" @submit.prevent="save">
      <CadenceFormSectionFrame :id="form.sections.identity.id">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.identity.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.identity.title"
          title-class="hud-label"
          divider-class="flex-1 h-px bg-base-300/60"
        />

        <CadenceField
          :control-id="form.fields.display_name.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.display_name.label"
          label-class="hud-label block mb-1.5"
        >
          <input
            :id="form.fields.display_name.id"
            v-model="spacecraft.display_name"
            :name="form.fields.display_name.name"
            :type="form.fields.display_name.type"
            :required="form.fields.display_name.required"
            class="w-full input"
            @input="validate"
          >
        </CadenceField>

        <CadenceField
          :control-id="form.fields.scid.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.scid.label"
          label-class="hud-label block mb-1.5"
        >
          <input
            :id="form.fields.scid.id"
            v-model="spacecraft.scid"
            :name="form.fields.scid.name"
            :type="form.fields.scid.type"
            :required="form.fields.scid.required"
            class="w-full input"
            @input="validate"
          >
        </CadenceField>
      </CadenceFormSectionFrame>

      <CadenceFormSectionFrame :id="form.sections.profile.id">
        <CadenceFormSectionHeader
          wrapper-class="flex items-center gap-3"
          :number="form.sections.profile.number"
          number-class="hud-label text-primary/70"
          :title="form.sections.profile.title"
          title-class="hud-label"
          divider-class="flex-1 h-px bg-base-300/60"
        />

        <CadenceField
          :control-id="form.fields.spacecraft_type_id.id"
          wrapper-class="fieldset mb-3"
          :label="form.fields.spacecraft_type_id.label"
          label-class="hud-label block mb-1.5"
        >
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
        </CadenceField>

        <p v-if="profile_options.empty" class="text-xs text-base-content/70">
          {{ profile_options.empty_state.message }}
          <a
            :id="profile_options.empty_state.action.id"
            :href="profile_options.empty_state.action.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="text-primary hover:underline"
          >{{ profile_options.empty_state.action.label }}</a>
          {{ profile_options.empty_state.suffix }}
        </p>
      </CadenceFormSectionFrame>

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
  </CadenceNarrowFormPageFrame>
</template>
