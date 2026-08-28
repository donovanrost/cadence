<script setup lang="ts">
import {reactive, watch} from "vue"
import CadenceFormActions from "./ui/components/CadenceFormActions.vue"
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"

type Breadcrumb = {
  label: string
  href: string | null
}

type MissionPage = {
  id: string
  heading: string
  breadcrumbs: Breadcrumb[]
}

type FormField = {
  id: string
  name: string
  type: "text"
  label: string
  required: boolean
  value: string
}

type MissionForm = {
  id: string
  fields: {
    display_name: FormField
    slug: FormField
  }
  actions: {
    submit: {id: string; label: string}
    cancel: {id: string; label: string; href: string}
  }
}

type MissionValues = {
  display_name: string
  slug: string
}

type MissionPayload = {
  mission: MissionValues
}

const props = defineProps<{
  page: MissionPage
  form: MissionForm
}>()

const emit = defineEmits<{
  validate: [payload: MissionPayload]
  save: [payload: MissionPayload]
}>()

const values = reactive<MissionValues>({
  display_name: props.form.fields.display_name.value,
  slug: props.form.fields.slug.value
})

watch(
  () => [props.form.fields.display_name.value, props.form.fields.slug.value] as const,
  ([displayName, slug], [previousDisplayName, previousSlug]) => {
    // Accept a server value only when no newer local edit has diverged from its prior prop.
    if (values.display_name === previousDisplayName) {
      values.display_name = displayName
    }

    if (values.slug === previousSlug) {
      values.slug = slug
    }
  }
)

const payload = (): MissionPayload => ({
  mission: {
    display_name: values.display_name,
    slug: values.slug
  }
})

const validate = () => emit("validate", payload())
const save = () => emit("save", payload())
</script>

<template>
  <div :id="page.id" class="space-y-6 max-w-xl">
    <CadencePageHeaderFrame variant="compact">
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
            {{ page.heading }}
          </h1>
        </div>
      </div>
    </CadencePageHeaderFrame>

    <form :id="form.id" class="space-y-6" @submit.prevent="save">
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

      <div class="fieldset mb-3">
        <label :for="form.fields.slug.id">
          <span class="hud-label block mb-1.5">{{ form.fields.slug.label }}</span>
          <input
            :id="form.fields.slug.id"
            v-model="values.slug"
            :name="form.fields.slug.name"
            :type="form.fields.slug.type"
            :required="form.fields.slug.required"
            class="w-full input"
            @input="validate"
          >
        </label>
      </div>

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
