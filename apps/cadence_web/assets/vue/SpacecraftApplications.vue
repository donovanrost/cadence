<script setup lang="ts">
import StatusBadge from "./StatusBadge.vue"
import CadenceDataRow from "./ui/components/CadenceDataRow.vue"

type StatusTone = "info" | "ready" | "attention" | "blocked"
type ButtonVariant = "primary" | "secondary" | "danger"
type LifecycleEvent = "install" | "disable" | "uninstall"

type ApplicationEvent = {
  key: string
}

type Confirmation = {
  title: string
  message: string
  confirm_label: string
  tone: "attention" | "danger"
  prompt: string
}

type LifecycleAction = {
  id: string
  action_id: string
  label: string
  variant: ButtonVariant
  effect: string
  execution: string
  confirmation: Confirmation | null
}

type StatusFact = {
  id: string
  label: string
  value: string | null
}

type ApplicationCard = {
  id: string
  application_key: string
  application_version: number | null
  display_name: string
  description: string
  lifecycle_state: string | null
  installable: boolean
  manageable: boolean
  uninstallable: boolean
  scope_label: string
  manage_path: string
  status: {
    state: string
    label: string
    tone: StatusTone
    facts: StatusFact[]
  }
  install_action: LifecycleAction | null
  disable_action: LifecycleAction | null
  uninstall_action: LifecycleAction | null
  unavailable_message: string | null
}

type MissingProfile = {
  kind: "missing"
  id: string
  label: string
  title: string
  description: string
  action: {
    label: string
    path: string
  }
}

type PinnedProfile = {
  kind: "pinned"
  id: string
  label: string
  display_name: string
  version: number
  status: {
    tone: "ready" | "attention"
    label: string
  }
}

const props = defineProps<{
  profile: MissingProfile | PinnedProfile
  applications: ApplicationCard[]
}>()

const emit = defineEmits<{
  install: [payload: ApplicationEvent]
  disable: [payload: ApplicationEvent]
  uninstall: [payload: ApplicationEvent]
}>()

const buttonClasses: Record<ButtonVariant, string> = {
  primary: "btn-primary",
  secondary: "btn-secondary",
  danger: "btn-error btn-outline"
}

const dispatch = (
  event: LifecycleEvent,
  application: ApplicationCard,
  action: LifecycleAction | null
) => {
  if (!action) return
  if (action.confirmation && !window.confirm(action.confirmation.prompt)) return

  emit(event, {key: application.application_key})
}
</script>

<template>
  <section id="spacecraft-applications-inventory" class="space-y-6">
    <section
      v-if="props.profile.kind === 'missing'"
      :id="props.profile.id"
      class="card border border-base-300 bg-base-200"
    >
      <div class="card-body p-6">
        <p class="hud-label">{{ props.profile.label }}</p>
        <h2 class="mt-2 text-base font-semibold">{{ props.profile.title }}</h2>
        <p class="mt-1 text-sm text-base-content/70">{{ props.profile.description }}</p>
        <a
          :href="props.profile.action.path"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-primary btn-sm mt-5"
        >{{ props.profile.action.label }}</a>
      </div>
    </section>

    <section
      v-else
      :id="props.profile.id"
      class="card border border-base-300 bg-base-200"
    >
      <div class="card-body p-6">
        <div class="flex items-start justify-between gap-4">
          <div>
            <p class="hud-label">{{ props.profile.label }}</p>
            <h2 class="mt-2 text-base font-semibold">
              {{ props.profile.display_name }}
              <span class="mc-value-small text-base-content/70">v{{ props.profile.version }}</span>
            </h2>
          </div>
          <StatusBadge :status="props.profile.status.tone" :label="props.profile.status.label" />
        </div>
      </div>
    </section>

    <section
      v-if="props.profile.kind === 'pinned' || props.applications.length > 0"
      id="spacecraft-applications-list"
      class="grid gap-4 lg:grid-cols-2"
    >
      <section
        v-for="application in props.applications"
        :id="application.id"
        :key="application.id"
        class="card border border-base-300 bg-base-200"
      >
        <div class="card-body p-6">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="hud-label">{{ application.scope_label }}</p>
              <h2 class="mt-2 text-base font-semibold">{{ application.display_name }}</h2>
            </div>
            <StatusBadge :status="application.status.tone" :label="application.status.label" />
          </div>

          <p class="mt-3 text-sm text-base-content/70">{{ application.description }}</p>

          <div class="mt-5 space-y-1">
            <CadenceDataRow
              v-for="fact in application.status.facts"
              :key="fact.id"
              row-class="hud-data-row"
              label-class="hud-data-label"
              :label="fact.label"
            >
              <span class="hud-data-value">{{ fact.value || "—" }}</span>
            </CadenceDataRow>
          </div>

          <div class="mt-5 flex flex-wrap items-center gap-2">
            <a
              v-if="application.manageable"
              :href="application.manage_path"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="btn btn-primary btn-sm"
            >Manage</a>

            <button
              v-if="application.install_action"
              :id="application.install_action.id"
              type="button"
              class="btn btn-primary btn-sm"
              @click="dispatch('install', application, application.install_action)"
            >{{ application.install_action.label }}</button>

            <button
              v-if="application.disable_action"
              :id="application.disable_action.id"
              type="button"
              class="btn btn-sm"
              :class="buttonClasses[application.disable_action.variant]"
              :data-application-lifecycle-action="application.disable_action.action_id"
              :data-lifecycle-effect="application.disable_action.effect"
              :data-lifecycle-execution="application.disable_action.execution"
              :data-confirmation-required="String(Boolean(application.disable_action.confirmation))"
              :data-confirmation-tone="application.disable_action.confirmation?.tone"
              :data-confirmation-title="application.disable_action.confirmation?.title"
              :data-confirmation-label="application.disable_action.confirmation?.confirm_label"
              :data-confirm="application.disable_action.confirmation?.prompt"
              @click.stop="dispatch('disable', application, application.disable_action)"
            >{{ application.disable_action.label }}</button>

            <button
              v-if="application.uninstall_action"
              :id="application.uninstall_action.id"
              type="button"
              class="btn btn-sm"
              :class="buttonClasses[application.uninstall_action.variant]"
              :data-application-lifecycle-action="application.uninstall_action.action_id"
              :data-lifecycle-effect="application.uninstall_action.effect"
              :data-lifecycle-execution="application.uninstall_action.execution"
              :data-confirmation-required="String(Boolean(application.uninstall_action.confirmation))"
              :data-confirmation-tone="application.uninstall_action.confirmation?.tone"
              :data-confirmation-title="application.uninstall_action.confirmation?.title"
              :data-confirmation-label="application.uninstall_action.confirmation?.confirm_label"
              :data-confirm="application.uninstall_action.confirmation?.prompt"
              @click.stop="dispatch('uninstall', application, application.uninstall_action)"
            >{{ application.uninstall_action.label }}</button>
          </div>

          <p v-if="application.unavailable_message" class="mt-5 text-xs text-base-content/50">
            {{ application.unavailable_message }}
          </p>
        </div>
      </section>
    </section>
  </section>
</template>
