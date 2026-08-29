<script setup lang="ts">
import CadenceOpsViewport from "./ui/components/CadenceOpsViewport.vue"
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"
import {reactive, watch} from "vue"

type Page = {
  id: string
  eyebrow: string
  heading: string
  copy: string
  list: {
    id: string
    empty: {
      id: string
      copy: string
    }
  }
  form_eyebrow: string
  present_action: {
    label: string
    icon: string
  }
}

type TextField = {
  id: string
  name: string
  type: "text" | "textarea"
  label: string
  value: string
  required: boolean
}

type DashboardIdsField = {
  id: string
  name: string
  type: "select"
  label: string
  value: string[]
  required: boolean
  multiple: boolean
}

type DwellSecondsField = {
  id: string
  name: string
  type: "number"
  label: string
  value: string
  required: boolean
  min: number
  max: number
}

type WallboardModeField = {
  id: string
  name: string
  type: "checkbox"
  label: string
  value: boolean
  required: boolean
}

type PlaylistForm = {
  id: string
  reset_revision: number
  name: TextField
  description: TextField
  dashboard_ids: DashboardIdsField
  dwell_seconds: DwellSecondsField
  wallboard_mode: WallboardModeField
  submit: {
    id: string
    label: string
  }
}

type DashboardOption = {
  label: string
  value: string
}

type DashboardPlaylist = {
  __dom_id: string
  dashboard_playlist_id: string
  name: string
  description: string | null
  dashboard_ids: string[]
  dashboard_count: number
  dwell_seconds: number
  wallboard_mode: boolean
  mode_label: "wallboard" | "presentation"
  present: {
    id: string
    href: string
  }
}

type PlaylistValues = {
  name: string
  description: string
  dashboard_ids: string[]
  dwell_seconds: string
  wallboard_mode: boolean
}

const props = defineProps<{
  page: Page
  form: PlaylistForm
  options: DashboardOption[]
  dashboard_playlists: DashboardPlaylist[]
}>()

const emit = defineEmits<{
  "create-playlist": [payload: {playlist: PlaylistValues}]
}>()

const valuesFromForm = (form: PlaylistForm): PlaylistValues => ({
  name: form.name.value,
  description: form.description.value,
  dashboard_ids: [...form.dashboard_ids.value],
  dwell_seconds: form.dwell_seconds.value,
  wallboard_mode: form.wallboard_mode.value
})

const playlistForm = reactive<PlaylistValues>(valuesFromForm(props.form))
let appliedResetRevision = props.form.reset_revision
let submittedValues: PlaylistValues | null = null

const valuesMatch = (left: PlaylistValues, right: PlaylistValues) =>
  left.name === right.name &&
  left.description === right.description &&
  left.dwell_seconds === right.dwell_seconds &&
  left.wallboard_mode === right.wallboard_mode &&
  left.dashboard_ids.length === right.dashboard_ids.length &&
  left.dashboard_ids.every((dashboardId, index) => dashboardId === right.dashboard_ids[index])

watch(
  () => props.form.reset_revision,
  (resetRevision) => {
    if (resetRevision === appliedResetRevision) return

    if (submittedValues && valuesMatch(playlistForm, submittedValues)) {
      Object.assign(playlistForm, valuesFromForm(props.form))
    }

    submittedValues = null
    appliedResetRevision = resetRevision
  }
)

const createPlaylist = () => {
  const playlist = {
    name: playlistForm.name,
    description: playlistForm.description,
    dashboard_ids: [...playlistForm.dashboard_ids],
    dwell_seconds: playlistForm.dwell_seconds,
    wallboard_mode: playlistForm.wallboard_mode
  }

  submittedValues = playlist

  emit("create-playlist", {
    playlist
  })
}

const updateDwellSeconds = (event: Event) => {
  playlistForm.dwell_seconds = (event.target as HTMLInputElement).value
}
</script>

<template>
  <CadenceOpsViewport :id="page.id">
    <CadencePageHeaderFrame variant="ops-author">
      <div class="mx-auto max-w-6xl">
        <p class="hud-label">{{ page.eyebrow }}</p>
        <h1 class="mt-1 text-2xl font-semibold">{{ page.heading }}</h1>
        <p class="mt-2 text-sm text-base-content/60">
          {{ page.copy }}
        </p>
      </div>
    </CadencePageHeaderFrame>
    <div class="mx-auto grid max-w-6xl gap-5 p-6 lg:grid-cols-[minmax(0,1fr)_22rem]">
      <div :id="page.list.id" class="space-y-3">
        <div
          :id="page.list.empty.id"
          class="hidden only:block border border-dashed border-base-300 p-8 text-center text-sm text-base-content/50"
        >{{ page.list.empty.copy }}</div>
        <article
          v-for="playlist in dashboard_playlists"
          :id="playlist.__dom_id"
          :key="playlist.dashboard_playlist_id"
          class="border border-base-300 bg-base-200/20 p-4"
        >
          <div class="flex items-start justify-between gap-4">
            <div>
              <h2 class="font-semibold">{{ playlist.name }}</h2>
              <p class="mt-1 text-xs text-base-content/55">{{ playlist.description }}</p>
            </div>
            <span class="badge badge-outline">{{ playlist.dashboard_count }} dashboards</span>
          </div>
          <p class="mt-3 font-mono text-xs text-base-content/50">
            {{ playlist.dwell_seconds }}s dwell · {{ playlist.mode_label }}
          </p>
          <a
            :id="playlist.present.id"
            :href="playlist.present.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="btn btn-outline btn-sm mt-3"
          >
            <span :class="[page.present_action.icon, 'h-4 w-4']"></span>
            {{ page.present_action.label }}
          </a>
        </article>
      </div>
      <aside>
        <form
          :id="form.id"
          class="space-y-3 border border-primary/30 bg-primary/5 p-4"
          @submit.prevent="createPlaylist"
        >
          <p class="hud-label">{{ page.form_eyebrow }}</p>
          <div class="fieldset mb-3">
            <label>
              <span class="hud-label block mb-1.5">{{ form.name.label }}</span>
              <input
                :id="form.name.id"
                v-model="playlistForm.name"
                :name="form.name.name"
                :type="form.name.type"
                :required="form.name.required"
                class="w-full input"
              >
            </label>
          </div>
          <div class="fieldset mb-3">
            <label>
              <span class="hud-label block mb-1.5">{{ form.description.label }}</span>
              <textarea
                :id="form.description.id"
                v-model="playlistForm.description"
                :name="form.description.name"
                :required="form.description.required"
                class="w-full textarea"
              ></textarea>
            </label>
          </div>
          <div class="fieldset mb-3">
            <label>
              <span class="hud-label block mb-1.5">{{ form.dashboard_ids.label }}</span>
              <select
                :id="form.dashboard_ids.id"
                v-model="playlistForm.dashboard_ids"
                :name="form.dashboard_ids.name"
                :required="form.dashboard_ids.required"
                :multiple="form.dashboard_ids.multiple"
                class="w-full select"
              >
                <option v-for="option in options" :key="option.value" :value="option.value">
                  {{ option.label }}
                </option>
              </select>
            </label>
          </div>
          <div class="fieldset mb-3">
            <label>
              <span class="hud-label block mb-1.5">{{ form.dwell_seconds.label }}</span>
              <input
                :id="form.dwell_seconds.id"
                :value="playlistForm.dwell_seconds"
                :name="form.dwell_seconds.name"
                :type="form.dwell_seconds.type"
                :required="form.dwell_seconds.required"
                :min="form.dwell_seconds.min"
                :max="form.dwell_seconds.max"
                class="w-full input"
                @input="updateDwellSeconds"
              >
            </label>
          </div>
          <div class="fieldset mb-3">
            <label class="flex cursor-pointer items-start gap-3">
              <input type="hidden" :name="form.wallboard_mode.name" value="false">
              <input
                :id="form.wallboard_mode.id"
                v-model="playlistForm.wallboard_mode"
                :name="form.wallboard_mode.name"
                :type="form.wallboard_mode.type"
                value="true"
                class="checkbox checkbox-sm mt-0.5"
              >
              <span>
                <span class="block text-sm font-medium">{{ form.wallboard_mode.label }}</span>
              </span>
            </label>
          </div>
          <button :id="form.submit.id" type="submit" class="btn btn-primary btn-sm">
            {{ form.submit.label }}
          </button>
        </form>
      </aside>
    </div>
  </CadenceOpsViewport>
</template>
