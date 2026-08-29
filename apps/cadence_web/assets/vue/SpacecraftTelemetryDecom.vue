<script setup lang="ts">
import {ref, watch} from "vue"
import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"
import CadenceCard from "./ui/components/CadenceCard.vue"
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"
import CadencePageTitle from "./ui/components/CadencePageTitle.vue"

type StatusTone = "ready" | "attention" | "blocked" | "info"
type PreflightState = "ready" | "attention" | "blocked"
type DiagnosticSeverity = "error" | "warning" | "info"
type ButtonVariant = "primary" | "secondary" | "danger"

type Breadcrumb = {
  id: string
  label: string
  href: string | null
}

type Page = {
  id: string
  title: string
  subtitle: string
  breadcrumbs: Breadcrumb[]
}

type Card = {
  id: string
}

type Status = {
  state: string
  tone: StatusTone
  label: string
  description: string
  saved_label: string | null
}

type Revision = {
  form_id: string
  field: {
    id: string
    name: string
    label: string
    value: string
    options: {label: string; value: string}[]
  }
  action: {
    id: string
    label: string
  }
}

type NoRevisions = {
  message: string
  action: {
    label: string
    href: string
  }
}

type PacketHandoff = {
  id: string
  label: string
  selection_count: number
  row_count: number
  summary_suffix: string
  detail: string
  action: {
    id: string
    label: string
    href: string
  }
}

type PreviewStat = {
  id: string
  label: string
  value: number
}

type DiagnosticItem = {
  id: string
  diagnostic_id: string
  code: string
  severity: DiagnosticSeverity
  title: string
  detail: string
  value: string | null
}

type Diagnostics = {
  id: string
  items_id: string
  role: "alert" | "status"
  severity: DiagnosticSeverity
  count: number
  total_count: number
  count_label: string
  label: string
  title: string
  description: string
  items: DiagnosticItem[]
}

type Preview = {
  id: string
  label: string
  empty_message: string | null
  stats: PreviewStat[]
  diagnostics: Diagnostics | null
}

type PreflightCheck = {
  id: string
  check_id: string
  category: string
  state: PreflightState
  title: string
  detail: string
  value: string | null
}

type Preflight = {
  id: string
  checks_id: string
  state: PreflightState
  activation_ready: boolean
  check_count: number
  application_version: number
  summary: string
  label: string
  checks: PreflightCheck[]
}

type PendingActivation = {
  id: string
  activation_request_id: string
  message_before: string
  message_after: string
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
  event: "enable" | "disable"
  label: string
  variant: ButtonVariant
  effect: string
  execution: string
  confirmation: Confirmation | null
  disabled: boolean
}

type LifecycleActions = {
  empty_message: string | null
  disable: LifecycleAction | null
  enable: LifecycleAction | null
}

const props = defineProps<{
  page: Page
  card: Card
  status: Status
  revision: Revision | null
  no_revisions: NoRevisions | null
  packet_handoff: PacketHandoff | null
  preview: Preview | null
  preflight: Preflight
  pending_activation: PendingActivation | null
  lifecycle_actions: LifecycleActions
}>()

const emit = defineEmits<{
  change_revision: [payload: {catalog_revision_id: string}]
  save_catalog_revision: [payload: Record<string, never>]
  enable: [payload: {"action-id": string}]
  disable: [payload: {"action-id": string}]
}>()

const selectedRevisionId = ref(props.revision?.field.value ?? "")

watch(
  () => props.revision?.field.value ?? "",
  (revisionId) => {
    selectedRevisionId.value = revisionId
  }
)

const changeRevision = () => {
  if (selectedRevisionId.value === "") return
  emit("change_revision", {catalog_revision_id: selectedRevisionId.value})
}

const dispatchLifecycle = (action: LifecycleAction) => {
  if (action.disabled) return
  if (action.confirmation && !window.confirm(action.confirmation.prompt)) return

  if (action.event === "enable") emit("enable", {"action-id": action.action_id})
  if (action.event === "disable") emit("disable", {"action-id": action.action_id})
}

const statusDotClasses: Record<StatusTone, string> = {
  ready: "bg-success",
  attention: "bg-warning",
  blocked: "bg-error",
  info: "bg-info"
}

const preflightIconClasses: Record<PreflightState, string> = {
  ready: "border-success/35 bg-success/10 text-success",
  attention: "border-warning/35 bg-warning/10 text-warning",
  blocked: "border-error/35 bg-error/10 text-error"
}

const preflightIcons: Record<PreflightState, string> = {
  ready: "hero-shield-check",
  attention: "hero-exclamation-circle",
  blocked: "hero-shield-exclamation"
}

const statusBadgeClasses: Record<PreflightState, string> = {
  ready: "bg-success/20 text-success",
  attention: "bg-warning/20 text-warning",
  blocked: "bg-error/20 text-error"
}

const checkRailClasses: Record<PreflightState, string> = {
  ready: "bg-success",
  attention: "bg-warning",
  blocked: "bg-error"
}

const checkIcons: Record<PreflightState, string> = {
  ready: "hero-check-circle",
  attention: "hero-exclamation-circle",
  blocked: "hero-x-circle"
}

const checkIconClasses: Record<PreflightState, string> = {
  ready: "text-success",
  attention: "text-warning",
  blocked: "text-error"
}

const diagnosticHeaderIcons: Record<DiagnosticSeverity, string> = {
  error: "hero-exclamation-triangle",
  warning: "hero-exclamation-circle",
  info: "hero-information-circle"
}

const diagnosticHeaderIconClasses: Record<DiagnosticSeverity, string> = {
  error: "border-error/35 bg-error/10 text-error",
  warning: "border-warning/35 bg-warning/10 text-warning",
  info: "border-info/35 bg-info/10 text-info"
}

const diagnosticBadgeClasses: Record<DiagnosticSeverity, string> = {
  error: "bg-error/20 text-error",
  warning: "bg-warning/20 text-warning",
  info: "bg-info/20 text-info"
}

const diagnosticRailClasses: Record<DiagnosticSeverity, string> = {
  error: "bg-error",
  warning: "bg-warning",
  info: "bg-info"
}

const diagnosticItemIcons: Record<DiagnosticSeverity, string> = {
  error: "hero-x-circle",
  warning: "hero-exclamation-circle",
  info: "hero-information-circle"
}

const diagnosticItemIconClasses: Record<DiagnosticSeverity, string> = {
  error: "size-4 shrink-0 text-error",
  warning: "size-4 shrink-0 text-warning",
  info: "size-4 shrink-0 text-info"
}

const buttonClasses: Record<ButtonVariant, string> = {
  primary: "btn-primary",
  secondary: "btn-secondary",
  danger: "btn-error btn-outline"
}
</script>

<template>
  <div :id="page.id" class="space-y-6">
    <CadencePageHeaderFrame variant="compact">
      <div>
        <div>
          <CadenceBreadcrumbs>
            <template v-for="(breadcrumb, index) in page.breadcrumbs" :key="breadcrumb.id">
              <span v-if="index > 0" class="text-base-content/20" aria-hidden="true">/</span>
              <span
                v-if="breadcrumb.href === null"
                :id="breadcrumb.id"
                class="text-primary/90"
              >{{ breadcrumb.label }}</span>
              <a
                v-else
                :id="breadcrumb.id"
                :href="breadcrumb.href"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="hover:text-primary transition-colors"
              >{{ breadcrumb.label }}</a>
            </template>
          </CadenceBreadcrumbs>
          <CadencePageTitle>
            {{ page.title }}
          </CadencePageTitle>
          <p class="mt-1 max-w-3xl text-sm text-base-content/70">{{ page.subtitle }}</p>
        </div>
      </div>
    </CadencePageHeaderFrame>

    <CadenceCard :id="card.id" class="card bg-base-200 border border-base-300" body-class="card-body p-6">
        <div class="space-y-4">
          <div class="flex items-center justify-between gap-2">
            <div class="flex items-center gap-2">
              <span
                class="rounded-full flex-shrink-0 w-2 h-2"
                :class="statusDotClasses[status.tone]"
              ></span>
              <span class="text-base-content/90">{{ status.label }}</span>
              <span class="text-sm text-base-content/70">— {{ status.description }}</span>
            </div>
            <span v-if="status.saved_label" class="hud-label">{{ status.saved_label }}</span>
          </div>

          <div class="border-t border-base-300/30"></div>

          <div v-if="no_revisions">
            <p class="text-sm text-base-content/70">{{ no_revisions.message }}</p>
            <a
              :href="no_revisions.action.href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="btn btn-ghost btn-sm mt-3"
            >{{ no_revisions.action.label }}</a>
          </div>

          <template v-else-if="revision && packet_handoff && preview">
            <form
              :id="revision.form_id"
              class="flex max-w-xl items-end gap-3"
            >
              <div class="fieldset mb-3">
                <label>
                  <span class="hud-label block mb-1.5">{{ revision.field.label }}</span>
                  <select
                    :id="revision.field.id"
                    v-model="selectedRevisionId"
                    :name="revision.field.name"
                    class="w-full select"
                    @change="changeRevision"
                  >
                    <option
                      v-for="option in revision.field.options"
                      :key="option.value"
                      :value="option.value"
                    >{{ option.label }}</option>
                  </select>
                </label>
              </div>
              <button
                :id="revision.action.id"
                type="button"
                class="btn btn-ghost btn-sm mb-3 shrink-0"
                @click="emit('save_catalog_revision', {})"
              >{{ revision.action.label }}</button>
            </form>

            <div class="border-t border-base-300/30"></div>

            <section
              :id="packet_handoff.id"
              class="grid gap-4 md:grid-cols-[minmax(0,1fr)_auto] md:items-center"
            >
              <div>
                <p class="hud-label">{{ packet_handoff.label }}</p>
                <p class="mt-2 text-sm text-base-content/70">
                  {{ packet_handoff.selection_count }} of {{ packet_handoff.row_count }}
                  {{ packet_handoff.summary_suffix }}
                </p>
                <p class="mt-1 text-xs text-base-content/50">{{ packet_handoff.detail }}</p>
              </div>
              <a
                :id="packet_handoff.action.id"
                :href="packet_handoff.action.href"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="btn btn-ghost btn-sm"
              >{{ packet_handoff.action.label }}</a>
            </section>

            <div class="border-t border-base-300/30"></div>

            <div :id="preview.id">
              <p class="hud-label mb-2">{{ preview.label }}</p>
              <p v-if="preview.empty_message" class="text-sm text-base-content/70">
                {{ preview.empty_message }}
              </p>
              <template v-else>
                <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
                  <div
                    v-for="stat in preview.stats"
                    :id="stat.id"
                    :key="stat.id"
                    class="border border-base-300 bg-base-200 px-3 py-2"
                  >
                    <p class="hud-label">{{ stat.label }}</p>
                    <p class="mt-1 font-mono text-xl text-base-content">{{ stat.value }}</p>
                  </div>
                </div>

                <div v-if="preview.diagnostics" class="mt-3">
                  <section
                    :id="preview.diagnostics.id"
                    :role="preview.diagnostics.role"
                    aria-live="polite"
                    :data-diagnostic-severity="preview.diagnostics.severity"
                    :data-diagnostic-count="preview.diagnostics.count"
                    :data-diagnostic-total="preview.diagnostics.total_count"
                    class="overflow-hidden border border-base-300/80 bg-base-200/30"
                  >
                  <header class="grid gap-4 border-b border-base-300/70 px-4 py-3 sm:grid-cols-[auto_minmax(0,1fr)_auto] sm:items-center">
                    <div
                      class="grid size-9 place-items-center border"
                      :class="diagnosticHeaderIconClasses[preview.diagnostics.severity]"
                    >
                      <span
                        class="size-4"
                        :class="diagnosticHeaderIcons[preview.diagnostics.severity]"
                        aria-hidden="true"
                      ></span>
                    </div>
                    <div class="min-w-0">
                      <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
                        <h2 class="text-sm font-semibold uppercase tracking-[0.14em]">
                          {{ preview.diagnostics.title }}
                        </h2>
                        <span class="font-mono text-[0.65rem] uppercase tracking-[0.16em] text-base-content/45">
                          {{ preview.diagnostics.count_label }}
                        </span>
                      </div>
                      <p class="mt-1 text-sm text-base-content/65">
                        {{ preview.diagnostics.description }}
                      </p>
                    </div>
                    <span
                      class="inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide"
                      :class="diagnosticBadgeClasses[preview.diagnostics.severity]"
                    >{{ preview.diagnostics.label }}</span>
                  </header>

                  <div :id="preview.diagnostics.items_id" class="divide-y divide-base-300/60">
                    <article
                      v-for="item in preview.diagnostics.items"
                      :id="item.id"
                      :key="item.diagnostic_id"
                      :data-diagnostic-code="item.code"
                      :data-diagnostic-severity="item.severity"
                      class="group grid grid-cols-[0.25rem_minmax(0,1fr)_auto] gap-4 px-4 py-3"
                    >
                      <span
                        class="rounded-full"
                        :class="diagnosticRailClasses[item.severity]"
                      ></span>
                      <div class="min-w-0">
                        <div class="flex flex-wrap items-center gap-2">
                          <span class="font-mono text-[0.62rem] uppercase tracking-[0.13em] text-base-content/45">
                            {{ item.code }}
                          </span>
                          <h3 class="text-sm font-medium text-base-content">{{ item.title }}</h3>
                        </div>
                        <p class="mt-1 text-xs leading-5 text-base-content/60">{{ item.detail }}</p>
                      </div>
                      <div class="flex items-center gap-3 self-center">
                        <span
                          v-if="item.value"
                          class="max-w-56 truncate font-mono text-xs text-base-content/65"
                        >{{ item.value }}</span>
                        <span
                          :class="[
                            diagnosticItemIcons[item.severity],
                            diagnosticItemIconClasses[item.severity]
                          ]"
                          aria-hidden="true"
                        ></span>
                      </div>
                    </article>
                  </div>
                  </section>
                </div>
              </template>
            </div>
          </template>

          <div class="border-t border-base-300/30"></div>

          <section
            :id="preflight.id"
            :data-preflight-state="preflight.state"
            :data-activation-ready="String(preflight.activation_ready)"
            class="overflow-hidden border border-base-300/80 bg-base-200/30"
          >
            <header class="grid gap-4 border-b border-base-300/70 px-4 py-4 sm:grid-cols-[auto_minmax(0,1fr)_auto] sm:items-center">
              <div
                class="grid size-10 place-items-center border"
                :class="preflightIconClasses[preflight.state]"
              >
                <span
                  class="size-5"
                  :class="preflightIcons[preflight.state]"
                  aria-hidden="true"
                ></span>
              </div>
              <div>
                <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
                  <h2 class="text-sm font-semibold uppercase tracking-[0.14em]">
                    Activation preflight
                  </h2>
                  <span class="font-mono text-[0.65rem] uppercase tracking-[0.16em] text-base-content/45">
                    {{ preflight.check_count }} checks · v{{ preflight.application_version }}
                  </span>
                </div>
                <p class="mt-1 text-sm text-base-content/65">{{ preflight.summary }}</p>
              </div>
              <span
                data-preflight-summary-status
                class="inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide"
                :class="statusBadgeClasses[preflight.state]"
              >{{ preflight.label }}</span>
            </header>

            <div :id="preflight.checks_id" class="divide-y divide-base-300/60">
              <article
                v-for="check in preflight.checks"
                :id="check.id"
                :key="check.check_id"
                :data-check-category="check.category"
                :data-check-state="check.state"
                class="group grid grid-cols-[0.25rem_minmax(0,1fr)_auto] gap-4 px-4 py-3"
              >
                <span class="rounded-full" :class="checkRailClasses[check.state]"></span>
                <div class="min-w-0">
                  <div class="flex flex-wrap items-center gap-2">
                    <span class="font-mono text-[0.62rem] uppercase tracking-[0.16em] text-base-content/45">
                      {{ check.category }}
                    </span>
                    <h3 class="text-sm font-medium text-base-content">{{ check.title }}</h3>
                  </div>
                  <p class="mt-1 text-xs leading-5 text-base-content/60">{{ check.detail }}</p>
                </div>
                <div class="flex items-center gap-3 self-center">
                  <span v-if="check.value" class="font-mono text-xs text-base-content/65">
                    {{ check.value }}
                  </span>
                  <span
                    class="size-4"
                    :class="[checkIcons[check.state], checkIconClasses[check.state]]"
                    aria-hidden="true"
                  ></span>
                </div>
              </article>
            </div>
          </section>

          <div class="border-t border-base-300/30"></div>

          <div v-if="lifecycle_actions.empty_message" class="flex justify-end">
            <p class="text-sm text-base-content/70">{{ lifecycle_actions.empty_message }}</p>
          </div>
          <div v-else class="space-y-3">
            <div
              v-if="pending_activation"
              :id="pending_activation.id"
              role="alert"
              class="border border-info/40 bg-info/10 px-4 py-3 text-sm text-base-content"
            >
              {{ pending_activation.message_before }}
              <span class="font-mono">{{ pending_activation.activation_request_id }}</span>
              {{ pending_activation.message_after }}
            </div>
            <div class="flex justify-end gap-2">
              <button
                v-if="lifecycle_actions.disable"
                :id="lifecycle_actions.disable.id"
                type="button"
                class="btn btn-sm"
                :class="buttonClasses[lifecycle_actions.disable.variant]"
                :data-application-lifecycle-action="lifecycle_actions.disable.action_id"
                :data-lifecycle-effect="lifecycle_actions.disable.effect"
                :data-lifecycle-execution="lifecycle_actions.disable.execution"
                :data-confirmation-required="String(Boolean(lifecycle_actions.disable.confirmation))"
                :data-confirmation-tone="lifecycle_actions.disable.confirmation?.tone"
                :data-confirmation-title="lifecycle_actions.disable.confirmation?.title"
                :data-confirmation-label="lifecycle_actions.disable.confirmation?.confirm_label"
                :data-confirm="lifecycle_actions.disable.confirmation?.prompt"
                :disabled="lifecycle_actions.disable.disabled"
                @click="dispatchLifecycle(lifecycle_actions.disable)"
              >{{ lifecycle_actions.disable.label }}</button>
              <button
                v-if="lifecycle_actions.enable"
                :id="lifecycle_actions.enable.id"
                type="button"
                class="btn btn-sm"
                :class="buttonClasses[lifecycle_actions.enable.variant]"
                :data-application-lifecycle-action="lifecycle_actions.enable.action_id"
                :data-lifecycle-effect="lifecycle_actions.enable.effect"
                :data-lifecycle-execution="lifecycle_actions.enable.execution"
                :data-confirmation-required="String(Boolean(lifecycle_actions.enable.confirmation))"
                :data-confirmation-tone="lifecycle_actions.enable.confirmation?.tone"
                :data-confirmation-title="lifecycle_actions.enable.confirmation?.title"
                :data-confirmation-label="lifecycle_actions.enable.confirmation?.confirm_label"
                :data-confirm="lifecycle_actions.enable.confirmation?.prompt"
                :disabled="lifecycle_actions.enable.disabled"
                @click="dispatchLifecycle(lifecycle_actions.enable)"
              >{{ lifecycle_actions.enable.label }}</button>
            </div>
          </div>
        </div>
    </CadenceCard>
  </div>
</template>
