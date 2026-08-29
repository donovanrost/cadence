<script setup lang="ts">
import {reactive, watch} from "vue"
import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"

import CadenceCard from "./ui/components/CadenceCard.vue"
import CadenceDataRow from "./ui/components/CadenceDataRow.vue"
import CadencePanel from "./ui/components/CadencePanel.vue"
import StatusBadge from "./StatusBadge.vue"

type EmptyPayload = Record<string, never>

type Breadcrumb = {
  label: string
  href: string | null
}

type EmptyState = {
  id: string
  text: string
}

type Page = {
  id: string
  header: {
    title: string
    subtitle: string
    config_label: string
    breadcrumbs: Breadcrumb[]
  }
  grants: {
    card_id: string
    heading: string
    subtitle: string
    stream_id: string
    empty: EmptyState
  }
  grant_form_card: {
    id: string
    heading: string
    subtitle: string
  }
  audit: {
    card_id: string
    heading: string
    subtitle: string
    stream_id: string
    empty: EmptyState
  }
}

type Action = {
  id: string
  label: string
  disabled: boolean
  payload: EmptyPayload
}

type Actions = {
  validate: Action & {icon: string}
  rotate: Action & {icon: string}
  revoke: (Action & {confirm: string}) | null
}

type Stat = {
  id: string
  label: string
  value: string | number
}

type Option = {
  label: string
  value: string
  disabled: boolean
}

type GrantValues = {
  mission_id: string
  allowed_services: string
  allowed_stations: string
  max_quota: string
  grant_reason: string
}

type GrantInputValues = Record<keyof GrantValues, string | number>

type GrantField = {
  key: keyof GrantValues
  id: string
  name: string
  type: "select" | "text" | "number"
  label: string
  value: string
  required: boolean
  min: number | null
  placeholder: string | null
  options: Option[]
}

type GrantForm = {
  id: string
  values: GrantValues
  fields: Record<keyof GrantValues, GrantField>
  action: {
    id: string
    label: string
  }
}

type Grant = {
  id: string
  __dom_id: string
  provider_account_grant_id: string
  mission_name: string
  version_label: string
  restriction_summary: string | null
  lifecycle: {
    status: "ready" | "blocked"
    label: string
  }
  revoke: {
    id: string
    label: string
    confirm: string
    payload: {"grant-id": string}
  } | null
}

type AuditEntry = {
  id: string
  __dom_id: string
  provider_audit_entry_id: string
  recorded_at: string
  action: string
  outcome: {
    status: "ready" | "blocked"
    label: string
  }
}

type Detail = {
  label: string
  value: string
  mono: boolean
  wrapper_id: string | null
}

type DetailCard = {
  id: string
  title: string
  rows: Detail[]
}

type Ingestion = DetailCard & {
  description: string
}

type Guardrails = {
  id: string
  title: string
  json: string
}

type Diagnostics = {
  id: string
  title: string
  columns: Detail[][]
}

const props = defineProps<{
  page: Page
  actions: Actions
  stats: Stat[]
  grant_form: GrantForm
  configuration: DetailCard
  ingestion: Ingestion
  guardrails: Guardrails
  diagnostics: Diagnostics
  account_grants: Grant[]
  account_audit: AuditEntry[]
}>()

const emit = defineEmits<{
  "validate-account": [payload: EmptyPayload]
  "rotate-credential": [payload: EmptyPayload]
  "revoke-credential": [payload: EmptyPayload]
  "grant-mission": [payload: {grant: GrantValues}]
  "revoke-grant": [payload: {"grant-id": string}]
}>()

const grantValues = reactive<GrantInputValues>({...props.grant_form.values})
const grantFieldOrder: Array<keyof GrantValues> = [
  "mission_id",
  "allowed_services",
  "allowed_stations",
  "max_quota",
  "grant_reason"
]

watch(
  () => props.grant_form.values,
  values => Object.assign(grantValues, values),
  {deep: true}
)

const grantMission = () =>
  emit("grant-mission", {
    grant: {
      mission_id: String(grantValues.mission_id ?? ""),
      allowed_services: String(grantValues.allowed_services ?? ""),
      allowed_stations: String(grantValues.allowed_stations ?? ""),
      max_quota: String(grantValues.max_quota ?? ""),
      grant_reason: String(grantValues.grant_reason ?? "")
    }
  })

const revokeCredential = () => {
  if (props.actions.revoke && window.confirm(props.actions.revoke.confirm)) {
    emit("revoke-credential", props.actions.revoke.payload)
  }
}

const revokeGrant = (grant: Grant) => {
  if (grant.revoke && window.confirm(grant.revoke.confirm)) {
    emit("revoke-grant", grant.revoke.payload)
  }
}
</script>

<template>
  <div :id="page.id" class="space-y-6">
    <CadencePageHeaderFrame variant="compact">
      <div class="flex items-end justify-between gap-4">
        <div>
          <CadenceBreadcrumbs>
            <template
              v-for="(breadcrumb, index) in page.header.breadcrumbs"
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
          <h1 class="mt-2 text-2xl font-bold text-base-content tracking-tight">
            {{ page.header.title }}
            <span class="ml-3 font-mono text-base text-base-content/60">
              <span class="font-mono text-xs text-base-content/60">
                {{ page.header.config_label }}
              </span>
            </span>
          </h1>
          <p class="mt-1 max-w-3xl text-sm text-base-content/70">
            {{ page.header.subtitle }}
          </p>
        </div>
        <div class="flex items-center gap-2">
          <button
            :id="actions.validate.id"
            type="button"
            class="btn btn-secondary btn-sm"
            :disabled="actions.validate.disabled"
            @click="emit('validate-account', actions.validate.payload)"
          >
            <span :class="[actions.validate.icon, 'h-4 w-4']"></span>
            {{ actions.validate.label }}
          </button>
          <button
            :id="actions.rotate.id"
            type="button"
            class="btn btn-primary btn-sm"
            :disabled="actions.rotate.disabled"
            @click="emit('rotate-credential', actions.rotate.payload)"
          >
            <span :class="[actions.rotate.icon, 'h-4 w-4']"></span>
            {{ actions.rotate.label }}
          </button>
          <button
            v-if="actions.revoke"
            :id="actions.revoke.id"
            type="button"
            class="btn btn-error btn-outline btn-sm"
            :data-confirm="actions.revoke.confirm"
            :disabled="actions.revoke.disabled"
            @click="revokeCredential"
          >
            {{ actions.revoke.label }}
          </button>
        </div>
      </div>
    </CadencePageHeaderFrame>

    <div class="grid gap-3 md:grid-cols-4">
      <div
        v-for="stat in stats"
        :id="stat.id"
        :key="stat.id"
        class="border border-base-300 bg-base-200 px-3 py-2"
      >
        <p class="hud-label">{{ stat.label }}</p>
        <p class="mt-1 font-mono text-xl text-base-content">{{ stat.value }}</p>
      </div>
    </div>

    <div class="grid gap-4 xl:grid-cols-[minmax(0,1.4fr)_minmax(20rem,0.6fr)]">
      <div class="space-y-4">
        <CadencePanel
          :id="page.grants.card_id"
          class="card bg-base-200 border border-base-300"
          header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
        >
          <template #header>
            <div>
              <h2 class="text-base font-semibold text-base-content">{{ page.grants.heading }}</h2>
              <p class="mt-1 text-xs text-base-content/70">{{ page.grants.subtitle }}</p>
            </div>
          </template>
          <div class="card-body p-0">
            <div :id="page.grants.stream_id" class="divide-y divide-base-300">
              <div
                :id="page.grants.empty.id"
                class="hidden only:block p-5 text-sm text-base-content/60"
              >
                {{ page.grants.empty.text }}
              </div>
              <div
                v-for="grant in account_grants"
                :id="grant.__dom_id"
                :key="grant.id"
                class="flex items-start justify-between gap-4 px-5 py-4"
              >
                <div>
                  <p class="font-medium">{{ grant.mission_name }}</p>
                  <p class="mt-1 font-mono text-xs text-base-content/50">
                    {{ grant.version_label }}
                  </p>
                  <p
                    v-if="grant.restriction_summary"
                    class="mt-2 text-xs text-base-content/60"
                  >
                    {{ grant.restriction_summary }}
                  </p>
                </div>
                <div class="flex items-center gap-2">
                  <StatusBadge
                    :status="grant.lifecycle.status"
                    :label="grant.lifecycle.label"
                  />
                  <button
                    v-if="grant.revoke"
                    :id="grant.revoke.id"
                    type="button"
                    class="btn btn-error btn-outline btn-xs"
                    :data-confirm="grant.revoke.confirm"
                    @click="revokeGrant(grant)"
                  >
                    {{ grant.revoke.label }}
                  </button>
                </div>
              </div>
            </div>
          </div>
        </CadencePanel>

        <CadencePanel
          :id="page.grant_form_card.id"
          class="card bg-base-200 border border-base-300"
          header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
        >
          <template #header>
            <div>
              <h2 class="text-base font-semibold text-base-content">
                {{ page.grant_form_card.heading }}
              </h2>
              <p class="mt-1 text-xs text-base-content/70">
                {{ page.grant_form_card.subtitle }}
              </p>
            </div>
          </template>
          <div class="card-body p-6">
            <form :id="grant_form.id" class="space-y-4" @submit.prevent="grantMission">
              <div
                v-for="fieldKey in grantFieldOrder"
                :key="fieldKey"
                class="fieldset mb-3"
              >
                <label>
                  <span class="hud-label block mb-1.5">{{ grant_form.fields[fieldKey].label }}</span>
                  <select
                    v-if="grant_form.fields[fieldKey].type === 'select'"
                    :id="grant_form.fields[fieldKey].id"
                    v-model="grantValues[fieldKey]"
                    :name="grant_form.fields[fieldKey].name"
                    :required="grant_form.fields[fieldKey].required"
                    class="w-full select"
                  >
                    <option
                      v-for="option in grant_form.fields[fieldKey].options"
                      :key="option.value"
                      :value="option.value"
                      :disabled="option.disabled"
                    >
                      {{ option.label }}
                    </option>
                  </select>
                  <input
                    v-else
                    :id="grant_form.fields[fieldKey].id"
                    v-model="grantValues[fieldKey]"
                    :name="grant_form.fields[fieldKey].name"
                    :type="grant_form.fields[fieldKey].type"
                    :placeholder="grant_form.fields[fieldKey].placeholder || undefined"
                    :required="grant_form.fields[fieldKey].required"
                    :min="grant_form.fields[fieldKey].min ?? undefined"
                    class="w-full input"
                  >
                </label>
              </div>
              <div class="flex justify-end">
                <button
                  :id="grant_form.action.id"
                  type="submit"
                  class="btn btn-primary btn-sm"
                >
                  {{ grant_form.action.label }}
                </button>
              </div>
            </form>
          </div>
        </CadencePanel>

        <CadencePanel
          :id="page.audit.card_id"
          class="card bg-base-200 border border-base-300"
          header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
        >
          <template #header>
            <div>
              <h2 class="text-base font-semibold text-base-content">{{ page.audit.heading }}</h2>
              <p class="mt-1 text-xs text-base-content/70">{{ page.audit.subtitle }}</p>
            </div>
          </template>
          <div class="card-body p-0">
            <div :id="page.audit.stream_id" class="divide-y divide-base-300">
              <div
                :id="page.audit.empty.id"
                class="hidden only:block p-5 text-sm text-base-content/60"
              >
                {{ page.audit.empty.text }}
              </div>
              <div
                v-for="entry in account_audit"
                :id="entry.__dom_id"
                :key="entry.id"
                class="grid gap-2 px-5 py-3 sm:grid-cols-[10rem_minmax(0,1fr)_6rem] sm:items-center"
              >
                <time class="font-mono text-xs text-base-content/50">{{ entry.recorded_at }}</time>
                <span class="text-sm">{{ entry.action }}</span>
                <StatusBadge :status="entry.outcome.status" :label="entry.outcome.label" />
              </div>
            </div>
          </div>
        </CadencePanel>
      </div>

      <aside class="space-y-4">
        <CadenceCard :id="configuration.id" class="card bg-base-200 border border-base-300" body-class="card-body p-6">
            <p class="hud-label">{{ configuration.title }}</p>
            <div class="mt-3 divide-y divide-base-300">
              <CadenceDataRow
                v-for="row in configuration.rows"
                :key="row.label"
                row-class="hud-data-row"
                label-class="hud-data-label"
                :label="row.label"
              >
                <span class="hud-data-value" :class="row.mono && 'font-mono text-sm'">
                  {{ row.value }}
                </span>
              </CadenceDataRow>
            </div>
        </CadenceCard>

        <CadenceCard :id="ingestion.id" class="card bg-base-200 border border-base-300" body-class="card-body p-6">
            <p class="hud-label">{{ ingestion.title }}</p>
            <div class="mt-3 divide-y divide-base-300">
              <template v-for="row in ingestion.rows" :key="row.label">
                <div v-if="row.wrapper_id" :id="row.wrapper_id">
                  <CadenceDataRow
                    row-class="hud-data-row"
                    label-class="hud-data-label"
                    :label="row.label"
                  >
                    <span class="hud-data-value" :class="row.mono && 'font-mono text-sm'">
                      {{ row.value }}
                    </span>
                  </CadenceDataRow>
                </div>
                <CadenceDataRow
                  v-else
                  row-class="hud-data-row"
                  label-class="hud-data-label"
                  :label="row.label"
                >
                  <span class="hud-data-value" :class="row.mono && 'font-mono text-sm'">
                    {{ row.value }}
                  </span>
                </CadenceDataRow>
              </template>
            </div>
            <p class="mt-3 text-xs text-base-content/50">
              {{ ingestion.description }}
            </p>
        </CadenceCard>

        <CadenceCard :id="guardrails.id" class="card bg-base-200 border border-base-300" body-class="card-body p-6">
            <p class="hud-label">{{ guardrails.title }}</p>
            <pre
              class="mt-3 max-h-72 overflow-auto bg-base-100/50 p-3 font-mono text-xs text-base-content/70"
              v-text="guardrails.json"
            ></pre>
        </CadenceCard>
      </aside>
    </div>

    <details
      :id="diagnostics.id"
      class="rounded border border-base-300 bg-base-200/60 p-4 text-sm"
    >
      <summary class="cursor-pointer hud-label hover:text-primary">{{ diagnostics.title }}</summary>
      <div class="mt-4 grid gap-4 lg:grid-cols-2">
        <div
          v-for="(column, columnIndex) in diagnostics.columns"
          :key="columnIndex"
          class="divide-y divide-base-300"
        >
          <CadenceDataRow
            v-for="row in column"
            :key="row.label"
            row-class="hud-data-row"
            label-class="hud-data-label"
            :label="row.label"
          >
            <span class="hud-data-value" :class="row.mono && 'font-mono text-sm'">
              {{ row.value }}
            </span>
          </CadenceDataRow>
        </div>
      </div>
    </details>
  </div>
</template>
