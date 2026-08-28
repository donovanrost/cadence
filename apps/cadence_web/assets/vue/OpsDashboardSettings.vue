<script setup lang="ts">
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"
import CadenceField from "./ui/components/CadenceField.vue"
import {reactive, watch} from "vue"

type EmptyState = {
  id: string
  copy: string
}

type Page = {
  id: string
  header: {
    eyebrow: string
    heading: string
    copy: string
    viewer: {
      id: string
      label: string
      href: string
    }
  }
  sharing: {
    id: string
    eyebrow: string
    heading: string
    copy: string
    list: {
      id: string
      empty: EmptyState
    }
  }
  snapshots: {
    id: string
    eyebrow: string
    heading: string
    list: {
      id: string
      empty: EmptyState
    }
  }
  portability: {
    eyebrow: string
    copy: string
    export: {
      id: string
      label: string
      icon: string
      href: string
    }
    deployments: {
      id: string
      empty: EmptyState
    }
  }
  access: {
    eyebrow: string
    heading: string
    copy: string
  }
  lifecycle: {
    eyebrow: string
    copy: string
    archive: {
      id: string
      label: string
      icon: string
      confirm: string
    }
  }
}

type TextField = {
  id: string
  name: string
  type: "text" | "textarea"
  label: string
  value: string
  required: boolean
  placeholder?: string
}

type Option = {
  label: string
  value: string
}

type SelectField = {
  id: string
  name: string
  type: "select"
  label: string
  value: string
  required: boolean
  options: Option[]
}

type NumberField = {
  id: string
  name: string
  type: "number"
  label: string
  value: string
  required: boolean
  min: number
  placeholder: string
}

type SubmitAction = {
  id: string
  label: string
}

type SettingsForm = {
  id: string
  fields: {
    name: TextField
    description: TextField
    tags: TextField
    defaults_json: TextField
  }
  submit: SubmitAction
}

type ShareForm = {
  id: string
  fields: {
    data_visibility: SelectField
    expires_in_hours: NumberField
  }
  submit: SubmitAction
}

type SnapshotForm = {
  id: string
  fields: {
    data_visibility: SelectField
  }
  submit: SubmitAction
}

type DashboardShare = {
  __dom_id: string
  dashboard_share_id: string
  access_policy: string
  data_visibility: string
  status: "active" | "revoked"
  open: {
    id: string
    href: string
  }
  revoke: {
    id: string
    payload: {
      "share-id": string
    }
  } | null
}

type DashboardSnapshot = {
  __dom_id: string
  dashboard_snapshot_id: string
  dashboard_version: number
  data_semantics: string
  data_visibility: string
  open: {
    id: string
    href: string
  }
}

type DashboardDeployment = {
  __dom_id: string
  dashboard_deployment_id: string
  environment: string
  dashboard_version: number
  artifact_digest_prefix: string
}

type SettingsValues = {
  name: string
  description: string
  tags: string
  defaults_json: string
}

type ShareValues = {
  data_visibility: string
  expires_in_hours: string
}

type SnapshotValues = {
  data_visibility: string
}

const props = defineProps<{
  page: Page
  settings_form: SettingsForm
  share_form: ShareForm
  snapshot_form: SnapshotForm
  dashboard_shares: DashboardShare[]
  dashboard_snapshots: DashboardSnapshot[]
  dashboard_deployments: DashboardDeployment[]
}>()

const emit = defineEmits<{
  "validate-settings": [payload: {settings: SettingsValues}]
  "save-settings": [payload: {settings: SettingsValues}]
  "create-share": [payload: {share: ShareValues}]
  "revoke-share": [payload: {"share-id": string}]
  "create-snapshot": [payload: {snapshot: SnapshotValues}]
  "archive-dashboard": [payload: Record<string, never>]
}>()

const settingsValuesFromForm = (form: SettingsForm): SettingsValues => ({
  name: form.fields.name.value,
  description: form.fields.description.value,
  tags: form.fields.tags.value,
  defaults_json: form.fields.defaults_json.value
})

const settings = reactive<SettingsValues>(settingsValuesFromForm(props.settings_form))
const pendingSettingsValidations: SettingsValues[] = []

const currentSettings = (): SettingsValues => ({
  name: settings.name,
  description: settings.description,
  tags: settings.tags,
  defaults_json: settings.defaults_json
})

const sameSettings = (left: SettingsValues, right: SettingsValues) =>
  left.name === right.name &&
  left.description === right.description &&
  left.tags === right.tags &&
  left.defaults_json === right.defaults_json

watch(
  () => props.settings_form,
  (serverForm) => {
    const serverValues = settingsValuesFromForm(serverForm)
    const acknowledgedIndex = pendingSettingsValidations.findIndex((sent) =>
      sameSettings(sent, serverValues)
    )
    const latestPending = pendingSettingsValidations[pendingSettingsValidations.length - 1]
    const hasNewerTyping =
      acknowledgedIndex >= 0
        ? acknowledgedIndex < pendingSettingsValidations.length - 1
        : latestPending !== undefined && !sameSettings(latestPending, serverValues)

    if (acknowledgedIndex >= 0) pendingSettingsValidations.splice(0, acknowledgedIndex + 1)

    if (!hasNewerTyping) Object.assign(settings, serverValues)
  },
  {deep: true}
)

const share = reactive<ShareValues>({
  data_visibility: props.share_form.fields.data_visibility.value,
  expires_in_hours: props.share_form.fields.expires_in_hours.value
})

const snapshot = reactive<SnapshotValues>({
  data_visibility: props.snapshot_form.fields.data_visibility.value
})

const settingsPayload = () => ({settings: currentSettings()})

const validateSettings = () => {
  pendingSettingsValidations.push(currentSettings())
  emit("validate-settings", settingsPayload())
}

const saveSettings = () => emit("save-settings", settingsPayload())

const createShare = () =>
  emit("create-share", {
    share: {
      data_visibility: share.data_visibility,
      expires_in_hours: share.expires_in_hours
    }
  })

const revokeShare = (dashboardShare: DashboardShare) => {
  if (dashboardShare.revoke !== null) emit("revoke-share", dashboardShare.revoke.payload)
}

const createSnapshot = () =>
  emit("create-snapshot", {
    snapshot: {
      data_visibility: snapshot.data_visibility
    }
  })

const archiveDashboard = () => {
  if (window.confirm(props.page.lifecycle.archive.confirm)) emit("archive-dashboard", {})
}
</script>

<template>
  <section :id="page.id" class="h-full overflow-y-auto bg-base-100">
    <CadencePageHeaderFrame variant="ops">
      <div class="mx-auto flex max-w-5xl items-end justify-between gap-4">
        <div>
          <p class="font-mono text-[0.65rem] uppercase tracking-[0.2em] text-primary/70">
            {{ page.header.eyebrow }}
          </p>
          <h1 class="mt-1 text-2xl font-bold tracking-tight">{{ page.header.heading }}</h1>
          <p class="mt-2 text-sm text-base-content/60">
            {{ page.header.copy }}
          </p>
        </div>
        <a
          :id="page.header.viewer.id"
          :href="page.header.viewer.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-ghost btn-sm"
        >{{ page.header.viewer.label }}</a>
      </div>
    </CadencePageHeaderFrame>

    <div
      class="mx-auto grid max-w-5xl gap-5 p-5 lg:grid-cols-[minmax(0,1fr)_18rem] lg:p-7"
    >
      <div class="space-y-5">
        <form
          :id="settings_form.id"
          class="space-y-5 border border-base-300 bg-base-200/20 p-5"
          @submit.prevent="saveSettings"
        >
          <CadenceField
            :control-id="settings_form.fields.name.id"
            wrapper-class="fieldset mb-3"
            :label="settings_form.fields.name.label"
            label-class="hud-label block mb-1.5"
          >
            <input
              :id="settings_form.fields.name.id"
              v-model="settings.name"
              :name="settings_form.fields.name.name"
              :type="settings_form.fields.name.type"
              :required="settings_form.fields.name.required"
              class="w-full input"
              @input="validateSettings"
            >
          </CadenceField>

          <CadenceField
            :control-id="settings_form.fields.description.id"
            wrapper-class="fieldset mb-3"
            :label="settings_form.fields.description.label"
            label-class="hud-label block mb-1.5"
          >
            <textarea
              :id="settings_form.fields.description.id"
              v-model="settings.description"
              :name="settings_form.fields.description.name"
              :required="settings_form.fields.description.required"
              class="w-full textarea"
              @input="validateSettings"
            ></textarea>
          </CadenceField>

          <CadenceField
            :control-id="settings_form.fields.tags.id"
            wrapper-class="fieldset mb-3"
            :label="settings_form.fields.tags.label"
            label-class="hud-label block mb-1.5"
          >
            <input
              :id="settings_form.fields.tags.id"
              v-model="settings.tags"
              :name="settings_form.fields.tags.name"
              :type="settings_form.fields.tags.type"
              :required="settings_form.fields.tags.required"
              :placeholder="settings_form.fields.tags.placeholder"
              class="w-full input"
              @input="validateSettings"
            >
          </CadenceField>

          <CadenceField
            :control-id="settings_form.fields.defaults_json.id"
            wrapper-class="fieldset mb-3"
            :label="settings_form.fields.defaults_json.label"
            label-class="hud-label block mb-1.5"
          >
            <textarea
              :id="settings_form.fields.defaults_json.id"
              v-model="settings.defaults_json"
              :name="settings_form.fields.defaults_json.name"
              :required="settings_form.fields.defaults_json.required"
              class="textarea textarea-bordered min-h-64 w-full font-mono text-xs"
              @input="validateSettings"
            ></textarea>
          </CadenceField>

          <div class="flex justify-end">
            <button
              :id="settings_form.submit.id"
              type="submit"
              class="btn btn-primary btn-sm"
            >{{ settings_form.submit.label }}</button>
          </div>
        </form>

        <section :id="page.sharing.id" class="border border-base-300 bg-base-200/20 p-5">
          <p class="hud-label">{{ page.sharing.eyebrow }}</p>
          <h2 class="mt-1 text-lg font-semibold">{{ page.sharing.heading }}</h2>
          <p class="mt-1 text-xs text-base-content/55">
            {{ page.sharing.copy }}
          </p>
          <form
            :id="share_form.id"
            class="mt-4 grid gap-3 sm:grid-cols-2"
            @submit.prevent="createShare"
          >
            <CadenceField
              :control-id="share_form.fields.data_visibility.id"
              wrapper-class="fieldset mb-3"
              :label="share_form.fields.data_visibility.label"
              label-class="hud-label block mb-1.5"
            >
              <select
                :id="share_form.fields.data_visibility.id"
                v-model="share.data_visibility"
                :name="share_form.fields.data_visibility.name"
                :required="share_form.fields.data_visibility.required"
                class="w-full select"
              >
                <option
                  v-for="option in share_form.fields.data_visibility.options"
                  :key="option.value"
                  :value="option.value"
                >{{ option.label }}</option>
              </select>
            </CadenceField>
            <CadenceField
              :control-id="share_form.fields.expires_in_hours.id"
              wrapper-class="fieldset mb-3"
              :label="share_form.fields.expires_in_hours.label"
              label-class="hud-label block mb-1.5"
            >
              <input
                :id="share_form.fields.expires_in_hours.id"
                v-model="share.expires_in_hours"
                :name="share_form.fields.expires_in_hours.name"
                :type="share_form.fields.expires_in_hours.type"
                :required="share_form.fields.expires_in_hours.required"
                :min="share_form.fields.expires_in_hours.min"
                :placeholder="share_form.fields.expires_in_hours.placeholder"
                class="w-full input"
              >
            </CadenceField>
            <button
              :id="share_form.submit.id"
              type="submit"
              class="btn btn-primary btn-sm sm:col-span-2"
            >{{ share_form.submit.label }}</button>
          </form>
          <div :id="page.sharing.list.id" class="mt-4 space-y-2">
            <p
              :id="page.sharing.list.empty.id"
              class="hidden only:block text-xs text-base-content/45"
            >{{ page.sharing.list.empty.copy }}</p>
            <article
              v-for="dashboardShare in dashboard_shares"
              :id="dashboardShare.__dom_id"
              :key="dashboardShare.dashboard_share_id"
              class="flex items-center gap-3 border border-base-300 bg-base-100 p-3 text-xs"
            >
              <div class="min-w-0 flex-1">
                <a
                  :id="dashboardShare.open.id"
                  :href="dashboardShare.open.href"
                  data-phx-link="redirect"
                  data-phx-link-state="push"
                  class="font-mono text-primary hover:underline"
                >{{ dashboardShare.dashboard_share_id }}</a>
                <p class="mt-1 text-base-content/50">
                  {{ dashboardShare.access_policy }} · {{ dashboardShare.data_visibility }} ·
                  {{ dashboardShare.status }}
                </p>
              </div>
              <button
                v-if="dashboardShare.revoke !== null"
                :id="dashboardShare.revoke.id"
                type="button"
                class="btn btn-ghost btn-xs"
                @click="revokeShare(dashboardShare)"
              >Revoke</button>
            </article>
          </div>
        </section>

        <section
          :id="page.snapshots.id"
          class="border border-base-300 bg-base-200/20 p-5"
        >
          <p class="hud-label">{{ page.snapshots.eyebrow }}</p>
          <h2 class="mt-1 text-lg font-semibold">{{ page.snapshots.heading }}</h2>
          <form
            :id="snapshot_form.id"
            class="mt-4 flex items-end gap-3"
            @submit.prevent="createSnapshot"
          >
            <CadenceField
              :control-id="snapshot_form.fields.data_visibility.id"
              wrapper-class="fieldset mb-3"
              :label="snapshot_form.fields.data_visibility.label"
              label-class="hud-label block mb-1.5"
            >
              <select
                :id="snapshot_form.fields.data_visibility.id"
                v-model="snapshot.data_visibility"
                :name="snapshot_form.fields.data_visibility.name"
                :required="snapshot_form.fields.data_visibility.required"
                class="w-full select"
              >
                <option
                  v-for="option in snapshot_form.fields.data_visibility.options"
                  :key="option.value"
                  :value="option.value"
                >{{ option.label }}</option>
              </select>
            </CadenceField>
            <button
              :id="snapshot_form.submit.id"
              type="submit"
              class="btn btn-primary btn-sm"
            >{{ snapshot_form.submit.label }}</button>
          </form>
          <div :id="page.snapshots.list.id" class="mt-4 space-y-2">
            <p
              :id="page.snapshots.list.empty.id"
              class="hidden only:block text-xs text-base-content/45"
            >{{ page.snapshots.list.empty.copy }}</p>
            <article
              v-for="dashboardSnapshot in dashboard_snapshots"
              :id="dashboardSnapshot.__dom_id"
              :key="dashboardSnapshot.dashboard_snapshot_id"
              class="border border-base-300 bg-base-100 p-3 text-xs"
            >
              <a
                :id="dashboardSnapshot.open.id"
                :href="dashboardSnapshot.open.href"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="font-mono text-primary hover:underline"
              >{{ dashboardSnapshot.dashboard_snapshot_id }}</a>
              <p class="mt-1 text-base-content/50">
                Version {{ dashboardSnapshot.dashboard_version }} ·
                {{ dashboardSnapshot.data_semantics }} · {{ dashboardSnapshot.data_visibility }}
              </p>
            </article>
          </div>
        </section>
      </div>

      <aside class="space-y-4">
        <section class="border border-primary/30 bg-primary/5 p-4">
          <p class="hud-label">{{ page.portability.eyebrow }}</p>
          <p class="mt-2 text-xs text-base-content/60">
            {{ page.portability.copy }}
          </p>
          <a
            :id="page.portability.export.id"
            :href="page.portability.export.href"
            class="btn btn-outline btn-sm mt-3"
          >
            <span :class="[page.portability.export.icon, 'h-4 w-4']"></span>
            {{ page.portability.export.label }}
          </a>
          <div :id="page.portability.deployments.id" class="mt-3 space-y-1">
            <p
              :id="page.portability.deployments.empty.id"
              class="hidden only:block text-[0.7rem] text-base-content/45"
            >{{ page.portability.deployments.empty.copy }}</p>
            <p
              v-for="deployment in dashboard_deployments"
              :id="deployment.__dom_id"
              :key="deployment.dashboard_deployment_id"
              class="font-mono text-[0.65rem] text-base-content/50"
            >
              {{ deployment.environment }} · v{{ deployment.dashboard_version }} ·
              {{ deployment.artifact_digest_prefix }}
            </p>
          </div>
        </section>
        <section class="border border-base-300 bg-base-200/20 p-4">
          <p class="hud-label">{{ page.access.eyebrow }}</p>
          <p class="mt-2 text-sm font-semibold">{{ page.access.heading }}</p>
          <p class="mt-1 text-xs text-base-content/55">
            {{ page.access.copy }}
          </p>
        </section>
        <section class="border border-error/30 bg-error/5 p-4">
          <p class="hud-label text-error">{{ page.lifecycle.eyebrow }}</p>
          <p class="mt-2 text-xs text-base-content/60">
            {{ page.lifecycle.copy }}
          </p>
          <button
            :id="page.lifecycle.archive.id"
            type="button"
            class="btn btn-ghost btn-sm mt-3 text-error"
            :data-confirm="page.lifecycle.archive.confirm"
            @click="archiveDashboard"
          >
            <span :class="[page.lifecycle.archive.icon, 'h-4 w-4']"></span>
            {{ page.lifecycle.archive.label }}
          </button>
        </section>
      </aside>
    </div>
  </section>
</template>
