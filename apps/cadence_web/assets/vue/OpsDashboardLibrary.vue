<script setup lang="ts">
import {reactive, watch} from "vue"
import CadenceField from "./ui/components/CadenceField.vue"

type Header = {
  id: string
  eyebrow: string
  heading: string
  copy: string
}

type Page = {
  id: string
  header: Header
  list: {
    id: string
    empty: {
      id: string
      copy: string
    }
  }
  paths: {
    dashboards: string
    library: string
  }
}

type Option = {
  label: string
  value: string
}

type LibraryOption = Option & {
  latest_version: number
}

type TextField = {
  id: string
  name: string
  type: "text" | "textarea" | "number"
  label: string
  value: string
  required: boolean
  min?: number
}

type SelectField = {
  id: string
  name: string
  type: "select"
  label: string
  value: string
  required: boolean
  placeholder: string
}

type Action = {
  id: string
  label: string
}

type ProgressiveDetails = {
  id: string
  summary_id: string
  summary: string
  open: boolean
}

type StageForm = {
  id: string
  eyebrow: string
  fields: {
    dashboard_id: SelectField
    item_id: SelectField
    version: TextField
  }
  action: Action
}

type CreateForm = {
  id: string
  reset_revision: number
  details: ProgressiveDetails
  fields: {
    name: TextField
    description: TextField
    change_summary: TextField
    widget_json: TextField
  }
  action: Action
}

type VersionForm = {
  id: string
  details: ProgressiveDetails
  fields: {
    item_id: SelectField
    change_summary: TextField
    widget_json: TextField
  }
  action: Action
}

type LibraryItemIdentity = {
  dashboard_library_item_id: string
  name: string
  description: string
  latest_version: number
  created_by: string | null
  updated_by: string | null
}

type LibraryVersion = {
  dashboard_library_version_id: string
  version: number
  change_summary: string
  created_by: string | null
  badge: {
    id: string
    label: string
  }
  detail_id: string
}

type LibraryConsumer = {
  dashboard_id: string
  dashboard_name: string
  placement_id: string
  version: number
  latest_version: number
  update_available: boolean
  id: string
  action_id: string
  path: string
}

type LibraryItem = {
  __dom_id: string
  item: LibraryItemIdentity
  versions: LibraryVersion[]
  compatibility: {
    widget_type_id: string
    widget_type_version: number | null
    binding_source: string | null
  }
  usage: {
    consumer_count: number
    outdated_count: number
    consumers: LibraryConsumer[]
  }
  details: {
    id: string
    summary_id: string
    summary: string
    versions_id: string
    consumers_id: string
    consumers_empty_id: string
  }
}

type StageValues = {
  dashboard_id: string
  item_id: string
  version: string
}

type CreateValues = {
  name: string
  description: string
  change_summary: string
  widget_json: string
}

type VersionValues = {
  item_id: string
  change_summary: string
  widget_json: string
}

const props = defineProps<{
  page: Page
  dashboard_options: Option[]
  library_options: LibraryOption[]
  stage_form: StageForm
  create_form: CreateForm
  version_form: VersionForm
  library_items: LibraryItem[]
}>()

const emit = defineEmits<{
  "stage-library-item": [payload: {library_add: StageValues}]
  "create-library-item": [payload: {library_item: CreateValues}]
  "add-library-version": [payload: {library_version: VersionValues}]
}>()

const stageValuesFromForm = (form: StageForm): StageValues => ({
  dashboard_id: form.fields.dashboard_id.value,
  item_id: form.fields.item_id.value,
  version: form.fields.version.value
})

const createValuesFromForm = (form: CreateForm): CreateValues => ({
  name: form.fields.name.value,
  description: form.fields.description.value,
  change_summary: form.fields.change_summary.value,
  widget_json: form.fields.widget_json.value
})

const versionValuesFromForm = (form: VersionForm): VersionValues => ({
  item_id: form.fields.item_id.value,
  change_summary: form.fields.change_summary.value,
  widget_json: form.fields.widget_json.value
})

const stageForm = reactive<StageValues>(stageValuesFromForm(props.stage_form))
const createForm = reactive<CreateValues>(createValuesFromForm(props.create_form))
const versionForm = reactive<VersionValues>(versionValuesFromForm(props.version_form))

let appliedCreateResetRevision = props.create_form.reset_revision
let submittedCreateValues: CreateValues | null = null

const createValuesMatch = (left: CreateValues, right: CreateValues) =>
  left.name === right.name &&
  left.description === right.description &&
  left.change_summary === right.change_summary &&
  left.widget_json === right.widget_json

watch(
  () => props.create_form.reset_revision,
  (resetRevision) => {
    if (resetRevision === appliedCreateResetRevision) return

    if (submittedCreateValues && createValuesMatch(createForm, submittedCreateValues)) {
      Object.assign(createForm, createValuesFromForm(props.create_form))
    }

    submittedCreateValues = null
    appliedCreateResetRevision = resetRevision
  }
)

const stageLibraryItem = () => {
  emit("stage-library-item", {
    library_add: {
      dashboard_id: stageForm.dashboard_id,
      item_id: stageForm.item_id,
      version: stageForm.version
    }
  })
}

const createLibraryItem = () => {
  const libraryItem = {
    name: createForm.name,
    description: createForm.description,
    change_summary: createForm.change_summary,
    widget_json: createForm.widget_json
  }

  submittedCreateValues = libraryItem
  emit("create-library-item", {library_item: libraryItem})
}

const addLibraryVersion = () => {
  emit("add-library-version", {
    library_version: {
      item_id: versionForm.item_id,
      change_summary: versionForm.change_summary,
      widget_json: versionForm.widget_json
    }
  })
}

const updateStageVersion = (event: Event) => {
  stageForm.version = (event.target as HTMLInputElement).value
}
</script>

<template>
  <section :id="page.id" class="h-full overflow-y-auto bg-base-100">
    <header
      :id="page.header.id"
      class="border-b border-primary/20 bg-base-200/70 px-6 py-5 hud-grid"
    >
      <div class="mx-auto max-w-6xl">
        <p class="hud-label">{{ page.header.eyebrow }}</p>
        <h1 class="mt-1 text-2xl font-semibold">{{ page.header.heading }}</h1>
        <p class="mt-2 max-w-3xl text-sm text-base-content/60">
          {{ page.header.copy }}
        </p>
      </div>
    </header>

    <div class="mx-auto grid max-w-6xl gap-5 p-6 lg:grid-cols-[minmax(0,1fr)_22rem]">
      <div :id="page.list.id" class="space-y-3">
        <div
          :id="page.list.empty.id"
          class="hidden only:block border border-dashed border-base-300 p-8 text-center text-sm text-base-content/50"
        >{{ page.list.empty.copy }}</div>

        <article
          v-for="entry in library_items"
          :id="entry.__dom_id"
          :key="entry.item.dashboard_library_item_id"
          class="border border-base-300 bg-base-200/20 p-4"
        >
          <div class="flex items-start justify-between gap-3">
            <div>
              <h2 class="font-semibold">{{ entry.item.name }}</h2>
              <p class="mt-1 text-xs text-base-content/55">{{ entry.item.description }}</p>
            </div>
            <span class="badge badge-outline font-mono">
              v{{ entry.item.latest_version }}
            </span>
          </div>

          <dl class="mt-4 grid grid-cols-3 gap-2 text-xs">
            <div>
              <dt class="hud-label">Consumers</dt>
              <dd class="mt-1 text-lg">{{ entry.usage.consumer_count }}</dd>
            </div>
            <div>
              <dt class="hud-label">Updates</dt>
              <dd class="mt-1 text-lg text-warning">{{ entry.usage.outdated_count }}</dd>
            </div>
            <div>
              <dt class="hud-label">Compatibility</dt>
              <dd class="mt-1 font-mono">{{ entry.compatibility.widget_type_id }}</dd>
            </div>
          </dl>

          <div class="mt-3 flex flex-wrap gap-1">
            <span
              v-for="version in entry.versions"
              :id="version.badge.id"
              :key="version.dashboard_library_version_id"
              class="badge badge-ghost font-mono"
            >{{ version.badge.label }}</span>
          </div>

          <details :id="entry.details.id" class="mt-3 border-t border-base-300/60 pt-3">
            <summary
              :id="entry.details.summary_id"
              class="cursor-pointer hud-label hover:text-primary"
            >{{ entry.details.summary }}</summary>

            <div class="mt-3 grid gap-3 text-xs md:grid-cols-2">
              <section :id="entry.details.versions_id">
                <p class="hud-label">Immutable versions</p>
                <dl class="mt-2 space-y-2">
                  <div
                    v-for="version in entry.versions"
                    :id="version.detail_id"
                    :key="version.dashboard_library_version_id + '-detail'"
                    class="border border-base-300/60 bg-base-100/40 p-2"
                  >
                    <dt class="font-mono">{{ version.badge.label }}</dt>
                    <dd class="mt-1 text-base-content/60">{{ version.change_summary }}</dd>
                  </div>
                </dl>
              </section>

              <section :id="entry.details.consumers_id">
                <p class="hud-label">Pinned consumers</p>
                <p
                  v-if="entry.usage.consumers.length === 0"
                  :id="entry.details.consumers_empty_id"
                  class="mt-2 text-base-content/50"
                >No pinned consumers.</p>
                <ul v-else class="mt-2 space-y-2">
                  <li
                    v-for="consumer in entry.usage.consumers"
                    :id="consumer.id"
                    :key="consumer.placement_id"
                    class="border border-base-300/60 bg-base-100/40 p-2"
                  >
                    <a
                      :id="consumer.action_id"
                      :href="consumer.path"
                      data-phx-link="redirect"
                      data-phx-link-state="push"
                      class="font-medium hover:text-primary"
                    >{{ consumer.dashboard_name }}</a>
                    <p class="mt-1 font-mono text-base-content/50">
                      v{{ consumer.version }} pinned
                      <span v-if="consumer.update_available">
                        · v{{ consumer.latest_version }} available
                      </span>
                    </p>
                  </li>
                </ul>
              </section>
            </div>
          </details>
        </article>
      </div>

      <aside class="space-y-4">
        <form
          :id="stage_form.id"
          class="space-y-3 border border-primary/30 bg-primary/5 p-4"
          @submit.prevent="stageLibraryItem"
        >
          <p class="hud-label">{{ stage_form.eyebrow }}</p>

          <CadenceField
            :control-id="stage_form.fields.dashboard_id.id"
            wrapper-class="fieldset mb-3"
            :label="stage_form.fields.dashboard_id.label"
            label-class="hud-label block mb-1.5"
          >
            <select
              :id="stage_form.fields.dashboard_id.id"
              v-model="stageForm.dashboard_id"
              :name="stage_form.fields.dashboard_id.name"
              :required="stage_form.fields.dashboard_id.required"
              class="w-full select"
            >
              <option value="">{{ stage_form.fields.dashboard_id.placeholder }}</option>
              <option
                v-for="option in dashboard_options"
                :key="option.value"
                :value="option.value"
              >{{ option.label }}</option>
            </select>
          </CadenceField>

          <CadenceField
            :control-id="stage_form.fields.item_id.id"
            wrapper-class="fieldset mb-3"
            :label="stage_form.fields.item_id.label"
            label-class="hud-label block mb-1.5"
          >
            <select
              :id="stage_form.fields.item_id.id"
              v-model="stageForm.item_id"
              :name="stage_form.fields.item_id.name"
              :required="stage_form.fields.item_id.required"
              class="w-full select"
            >
              <option value="">{{ stage_form.fields.item_id.placeholder }}</option>
              <option
                v-for="option in library_options"
                :key="option.value"
                :value="option.value"
              >{{ option.label }}</option>
            </select>
          </CadenceField>

          <CadenceField
            :control-id="stage_form.fields.version.id"
            wrapper-class="fieldset mb-3"
            :label="stage_form.fields.version.label"
            label-class="hud-label block mb-1.5"
          >
            <input
              :id="stage_form.fields.version.id"
              :value="stageForm.version"
              :name="stage_form.fields.version.name"
              :type="stage_form.fields.version.type"
              :required="stage_form.fields.version.required"
              :min="stage_form.fields.version.min"
              class="w-full input"
              @input="updateStageVersion"
            >
          </CadenceField>

          <button :id="stage_form.action.id" type="submit" class="btn btn-primary btn-sm">
            {{ stage_form.action.label }}
          </button>
        </form>

        <details
          :id="create_form.details.id"
          :open="create_form.details.open"
          class="border border-base-300 bg-base-200/20 p-4"
        >
          <summary
            :id="create_form.details.summary_id"
            class="cursor-pointer font-semibold"
          >{{ create_form.details.summary }}</summary>

          <form
            :id="create_form.id"
            class="mt-4 space-y-3"
            @submit.prevent="createLibraryItem"
          >
            <CadenceField
              :control-id="create_form.fields.name.id"
              wrapper-class="fieldset mb-3"
              :label="create_form.fields.name.label"
              label-class="hud-label block mb-1.5"
            >
              <input
                :id="create_form.fields.name.id"
                v-model="createForm.name"
                :name="create_form.fields.name.name"
                :type="create_form.fields.name.type"
                :required="create_form.fields.name.required"
                class="w-full input"
              >
            </CadenceField>

            <CadenceField
              :control-id="create_form.fields.description.id"
              wrapper-class="fieldset mb-3"
              :label="create_form.fields.description.label"
              label-class="hud-label block mb-1.5"
            >
              <textarea
                :id="create_form.fields.description.id"
                v-model="createForm.description"
                :name="create_form.fields.description.name"
                :required="create_form.fields.description.required"
                class="w-full textarea"
              ></textarea>
            </CadenceField>

            <CadenceField
              :control-id="create_form.fields.change_summary.id"
              wrapper-class="fieldset mb-3"
              :label="create_form.fields.change_summary.label"
              label-class="hud-label block mb-1.5"
            >
              <input
                :id="create_form.fields.change_summary.id"
                v-model="createForm.change_summary"
                :name="create_form.fields.change_summary.name"
                :type="create_form.fields.change_summary.type"
                :required="create_form.fields.change_summary.required"
                class="w-full input"
              >
            </CadenceField>

            <CadenceField
              :control-id="create_form.fields.widget_json.id"
              wrapper-class="fieldset mb-3"
              :label="create_form.fields.widget_json.label"
              label-class="hud-label block mb-1.5"
            >
              <textarea
                :id="create_form.fields.widget_json.id"
                v-model="createForm.widget_json"
                :name="create_form.fields.widget_json.name"
                :required="create_form.fields.widget_json.required"
                class="textarea textarea-bordered min-h-72 w-full font-mono text-xs"
              ></textarea>
            </CadenceField>

            <button :id="create_form.action.id" type="submit" class="btn btn-primary btn-sm">
              {{ create_form.action.label }}
            </button>
          </form>
        </details>

        <details
          :id="version_form.details.id"
          :open="version_form.details.open"
          class="border border-base-300 bg-base-200/20 p-4"
        >
          <summary
            :id="version_form.details.summary_id"
            class="cursor-pointer font-semibold"
          >{{ version_form.details.summary }}</summary>

          <form
            :id="version_form.id"
            class="mt-4 space-y-3"
            @submit.prevent="addLibraryVersion"
          >
            <CadenceField
              :control-id="version_form.fields.item_id.id"
              wrapper-class="fieldset mb-3"
              :label="version_form.fields.item_id.label"
              label-class="hud-label block mb-1.5"
            >
              <select
                :id="version_form.fields.item_id.id"
                v-model="versionForm.item_id"
                :name="version_form.fields.item_id.name"
                :required="version_form.fields.item_id.required"
                class="w-full select"
              >
                <option value="">{{ version_form.fields.item_id.placeholder }}</option>
                <option
                  v-for="option in library_options"
                  :key="option.value"
                  :value="option.value"
                >{{ option.label }}</option>
              </select>
            </CadenceField>

            <CadenceField
              :control-id="version_form.fields.change_summary.id"
              wrapper-class="fieldset mb-3"
              :label="version_form.fields.change_summary.label"
              label-class="hud-label block mb-1.5"
            >
              <input
                :id="version_form.fields.change_summary.id"
                v-model="versionForm.change_summary"
                :name="version_form.fields.change_summary.name"
                :type="version_form.fields.change_summary.type"
                :required="version_form.fields.change_summary.required"
                class="w-full input"
              >
            </CadenceField>

            <CadenceField
              :control-id="version_form.fields.widget_json.id"
              wrapper-class="fieldset mb-3"
              :label="version_form.fields.widget_json.label"
              label-class="hud-label block mb-1.5"
            >
              <textarea
                :id="version_form.fields.widget_json.id"
                v-model="versionForm.widget_json"
                :name="version_form.fields.widget_json.name"
                :required="version_form.fields.widget_json.required"
                class="textarea textarea-bordered min-h-72 w-full font-mono text-xs"
              ></textarea>
            </CadenceField>

            <button :id="version_form.action.id" type="submit" class="btn btn-primary btn-sm">
              {{ version_form.action.label }}
            </button>
          </form>
        </details>
      </aside>
    </div>
  </section>
</template>
