<script setup lang="ts">
import {reactive, watch} from "vue"

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

type Section = {
  id: string
  number: string
  title: string
}

type Field = {
  id: string
  name: string
  type: "text" | "textarea"
  label: string
  required: boolean
  disabled: boolean
  placeholder: string | null
  value: string
}

type GroundStationForm = {
  id: string
  sections: {
    identity: Section
    network: Section
    metadata: Section
  }
  fields: {
    ground_station_id: Field
    display_name: Field
    provider: Field
    region: Field
    metadata_json: Field
  }
  actions: {
    submit: {id: string; label: string}
    cancel: {id: string; label: string; href: string}
  }
}

type GroundStationValues = {
  ground_station_id: string
  display_name: string
  provider: string
  region: string
  metadata_json: string
}

type GroundStationPayload = {
  ground_station: GroundStationValues
}

const props = defineProps<{
  page: Page
  mode: "new" | "edit"
  form: GroundStationForm
}>()

const emit = defineEmits<{
  validate: [payload: GroundStationPayload]
  save: [payload: GroundStationPayload]
}>()

const formValues = (form: GroundStationForm): GroundStationValues => ({
  ground_station_id: form.fields.ground_station_id.value,
  display_name: form.fields.display_name.value,
  provider: form.fields.provider.value,
  region: form.fields.region.value,
  metadata_json: form.fields.metadata_json.value
})

const groundStation = reactive<GroundStationValues>(formValues(props.form))
const pendingValidations: GroundStationValues[] = []

const values = (): GroundStationValues => ({
  ground_station_id: groundStation.ground_station_id,
  display_name: groundStation.display_name,
  provider: groundStation.provider,
  region: groundStation.region,
  metadata_json: groundStation.metadata_json
})

const sameValues = (left: GroundStationValues, right: GroundStationValues) =>
  left.ground_station_id === right.ground_station_id &&
  left.display_name === right.display_name &&
  left.provider === right.provider &&
  left.region === right.region &&
  left.metadata_json === right.metadata_json

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

    if (!hasNewerTyping) Object.assign(groundStation, serverValues)
  },
  {deep: true}
)

const validate = () => {
  const currentValues = values()
  pendingValidations.push(currentValues)
  emit("validate", {ground_station: currentValues})
}

const save = () => emit("save", {ground_station: values()})
</script>

<template>
  <div :id="page.id" class="space-y-6 max-w-2xl" :data-mode="mode">
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
            {{ page.heading }}
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
          <label :for="form.fields.ground_station_id.id">
            <span class="hud-label block mb-1.5">{{ form.fields.ground_station_id.label }}</span>
            <input
              :id="form.fields.ground_station_id.id"
              v-model="groundStation.ground_station_id"
              :name="form.fields.ground_station_id.name"
              :type="form.fields.ground_station_id.type"
              :placeholder="form.fields.ground_station_id.placeholder ?? undefined"
              :required="form.fields.ground_station_id.required"
              :disabled="form.fields.ground_station_id.disabled"
              class="w-full input"
              @input="validate"
            >
          </label>
        </div>

        <div class="fieldset mb-3">
          <label :for="form.fields.display_name.id">
            <span class="hud-label block mb-1.5">{{ form.fields.display_name.label }}</span>
            <input
              :id="form.fields.display_name.id"
              v-model="groundStation.display_name"
              :name="form.fields.display_name.name"
              :type="form.fields.display_name.type"
              :placeholder="form.fields.display_name.placeholder ?? undefined"
              :required="form.fields.display_name.required"
              :disabled="form.fields.display_name.disabled"
              class="w-full input"
              @input="validate"
            >
          </label>
        </div>
      </section>

      <section :id="form.sections.network.id" class="space-y-4">
        <div class="flex items-center gap-3">
          <span class="hud-label text-primary/70">{{ form.sections.network.number }}</span>
          <h2 class="hud-label">{{ form.sections.network.title }}</h2>
          <div class="flex-1 h-px bg-base-300/60"></div>
        </div>

        <div class="fieldset mb-3">
          <label :for="form.fields.provider.id">
            <span class="hud-label block mb-1.5">{{ form.fields.provider.label }}</span>
            <input
              :id="form.fields.provider.id"
              v-model="groundStation.provider"
              :name="form.fields.provider.name"
              :type="form.fields.provider.type"
              :placeholder="form.fields.provider.placeholder ?? undefined"
              :required="form.fields.provider.required"
              :disabled="form.fields.provider.disabled"
              class="w-full input"
              @input="validate"
            >
          </label>
        </div>

        <div class="fieldset mb-3">
          <label :for="form.fields.region.id">
            <span class="hud-label block mb-1.5">{{ form.fields.region.label }}</span>
            <input
              :id="form.fields.region.id"
              v-model="groundStation.region"
              :name="form.fields.region.name"
              :type="form.fields.region.type"
              :placeholder="form.fields.region.placeholder ?? undefined"
              :required="form.fields.region.required"
              :disabled="form.fields.region.disabled"
              class="w-full input"
              @input="validate"
            >
          </label>
        </div>
      </section>

      <section :id="form.sections.metadata.id" class="space-y-4">
        <div class="flex items-center gap-3">
          <span class="hud-label text-primary/70">{{ form.sections.metadata.number }}</span>
          <h2 class="hud-label">{{ form.sections.metadata.title }}</h2>
          <div class="flex-1 h-px bg-base-300/60"></div>
        </div>

        <div class="fieldset mb-3">
          <label :for="form.fields.metadata_json.id">
            <span class="hud-label block mb-1.5">{{ form.fields.metadata_json.label }}</span>
            <textarea
              :id="form.fields.metadata_json.id"
              v-model="groundStation.metadata_json"
              :name="form.fields.metadata_json.name"
              :placeholder="form.fields.metadata_json.placeholder ?? undefined"
              :required="form.fields.metadata_json.required"
              :disabled="form.fields.metadata_json.disabled"
              class="w-full textarea min-h-40 font-mono text-xs"
              @input="validate"
            ></textarea>
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
