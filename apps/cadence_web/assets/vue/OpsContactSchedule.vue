<script setup lang="ts">
import {reactive, watch} from "vue"

type Option = {
  label: string
  value: string
}

type FormValues = {
  spacecraft_id: string
  route_key: string
  starts_at: string
  ends_at: string
}

type SelectField = {
  id: string
  name: string
  type: "select"
  label: string
  options: Option[]
}

type DateTimeField = {
  id: string
  name: string
  type: "datetime-local"
  label: string
}

type ActionState = {
  busy: boolean
  disabled: boolean
}

type ContactRecord = {
  __dom_id: string
  id: string
  kind: "scheduled" | "realized"
  state: string
  status: {
    label: string
    class: string
  }
  record_kind_label: string
  window: {
    starts_at: string
    ends_at: string
  }
  intent: string
  source_endpoints: string
  inspect_action: {
    id: string
    label: string
    icon: string
    href: string
  }
  telemetry_handoff: {
    owner: string
    window_available: boolean
  }
}

type Opportunity = {
  __dom_id: string
  id: string
  provider: string
  window: {
    starts_at: string
    ends_at: string
  }
  service_summary: string
  delivery: string
  antenna: string
  cost: number | string | null
  reserve_action: {
    id: string
    label: string
    busy_label: string
    busy: boolean
    disabled: boolean
    payload: {token: string}
  }
}

type Observation = {
  id: string
  label: string
  value: string | number | null
}

type ReservationReference = {
  id: string
  label: string
  display: string | null
  version: string | number | null
}

type Reservation = {
  __dom_id: string
  id: string
  state: string
  status: {
    label: string
    class: string
  }
  provider_status: string
  window: {
    starts_at: string
    ends_at: string
  }
  cancel_action: {
    id: string
    label: string
    confirm: string
    busy: boolean
    disabled: boolean
    payload: {"reservation-id": string}
  } | null
  detail_action: {
    id: string
    label: string
    icon: string
    href: string
  }
  observations: Observation[]
  provider: ReservationReference
  transport: ReservationReference
  service: ReservationReference
  delivery: ReservationReference
  uncertain: boolean
  configuration_failure: boolean
  diagnostics: {
    id: string
    title: string
    rows: Array<{label: string; value: string}>
  } | null
}

const props = defineProps<{
  page: {
    id: string
    header: {
      eyebrow: string
      title: string
      description: string
      scope: {label: string; value: string}
      contact_count: {id: string; label: string; value: number}
      reservation_count: {id: string; label: string; value: number}
    }
    contact_ledger: {
      id: string
      eyebrow: string
      title: string
      description: string
      timeline_action: {id: string; label: string; icon: string; href: string}
      rows_id: string
      empty: {id: string; icon: string; copy: string; visible: boolean}
    }
    opportunity_search: {eyebrow: string; description: string; icon: string}
    opportunities: {
      eyebrow: string
      description: string
      count: {id: string; value: number}
      rows_id: string
      empty: {id: string; icon: string; copy: string; visible: boolean}
    }
    reservations: {
      eyebrow: string
      description: string
      rows_id: string
      empty: {id: string; icon: string; copy: string; visible: boolean}
    }
  }
  search: {
    id: string
    values: FormValues
    fields: {
      spacecraft: SelectField
      route: SelectField
      starts_at: DateTimeField
      ends_at: DateTimeField
    }
    submit: {
      id: string
      label: string
      busy: boolean
      disabled: boolean
    }
    error: {id: string; message: string} | null
  }
  readiness: {
    id: string
    title: string
    findings: Array<{message: string}>
    action: {label: string; icon: string; href: string}
  } | null
  busy: {
    keys: string[]
    actions: Record<string, ActionState>
  }
  contact_records: ContactRecord[]
  opportunities: Opportunity[]
  provider_reservations: Reservation[]
}>()

const emit = defineEmits<{
  validate: [payload: {contact_search: FormValues}]
  search: [payload: {contact_search: FormValues}]
  reserve: [payload: {token: string}]
  cancel: [payload: {"reservation-id": string}]
}>()

const formValues = reactive<FormValues>({...props.search.values})

watch(
  () => props.search.values,
  values => Object.assign(formValues, values),
  {deep: true}
)

const updateField = (field: keyof FormValues, event: Event) => {
  formValues[field] = (event.target as HTMLInputElement | HTMLSelectElement).value
  emit("validate", {contact_search: {...formValues}})
}

const submitSearch = () => {
  emit("search", {contact_search: {...formValues}})
}

const actionState = (id: string, fallback: ActionState): ActionState => {
  return props.busy.actions[id] ?? fallback
}

const reserve = (opportunity: Opportunity) => {
  const state = actionState(opportunity.id, opportunity.reserve_action)
  if (!state.disabled) emit("reserve", opportunity.reserve_action.payload)
}

const cancel = (reservation: Reservation) => {
  if (!reservation.cancel_action) return

  const state = actionState(reservation.id, reservation.cancel_action)
  if (state.disabled) return

  if (window.confirm(reservation.cancel_action.confirm)) {
    emit("cancel", reservation.cancel_action.payload)
  }
}
</script>

<template>
  <section :id="page.id" class="h-full overflow-y-auto bg-base-100">
    <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">
      <div class="mx-auto flex max-w-[96rem] flex-col gap-4 md:flex-row md:items-end md:justify-between">
        <div>
          <p class="font-mono text-[0.65rem] uppercase tracking-[0.28em] text-primary/70">
            {{ page.header.eyebrow }}
          </p>
          <h1 class="mt-1 text-2xl font-bold tracking-tight text-base-content">
            {{ page.header.title }}
          </h1>
          <p class="mt-2 max-w-2xl text-sm text-base-content/60">
            {{ page.header.description }}
          </p>
        </div>
        <div class="flex items-center gap-4 border-l border-primary/30 pl-4 font-mono text-xs">
          <div>
            <p class="hud-label">{{ page.header.scope.label }}</p>
            <p class="mt-1 text-base-content/70">{{ page.header.scope.value }}</p>
          </div>
          <div>
            <p class="hud-label">{{ page.header.contact_count.label }}</p>
            <p :id="page.header.contact_count.id" class="mt-1 text-primary">
              {{ page.header.contact_count.value }}
            </p>
          </div>
          <div>
            <p class="hud-label">{{ page.header.reservation_count.label }}</p>
            <p :id="page.header.reservation_count.id" class="mt-1 text-primary">
              {{ page.header.reservation_count.value }}
            </p>
          </div>
        </div>
      </div>
    </header>

    <div class="mx-auto max-w-[96rem] p-5 lg:p-7">
      <section
        :id="page.contact_ledger.id"
        class="border border-base-300 bg-base-200/20 shadow-sm"
      >
        <div class="flex flex-col gap-3 border-b border-base-300 px-4 py-3 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <p class="hud-label">{{ page.contact_ledger.eyebrow }}</p>
            <h2 class="mt-1 text-base font-semibold">{{ page.contact_ledger.title }}</h2>
            <p class="mt-1 text-sm text-base-content/60">
              {{ page.contact_ledger.description }}
            </p>
          </div>
          <a
            :id="page.contact_ledger.timeline_action.id"
            :href="page.contact_ledger.timeline_action.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="btn btn-sm btn-ghost justify-start"
          >
            <span :class="[page.contact_ledger.timeline_action.icon, 'h-4 w-4']"></span>
            {{ page.contact_ledger.timeline_action.label }}
          </a>
        </div>
        <div :id="page.contact_ledger.rows_id">
          <div
            :id="page.contact_ledger.empty.id"
            class="hidden only:block px-4 py-12 text-center"
          >
            <span
              :class="[page.contact_ledger.empty.icon, 'mx-auto h-6 w-6 text-base-content/30']"
            ></span>
            <p class="mt-3 text-sm text-base-content/55">{{ page.contact_ledger.empty.copy }}</p>
          </div>
          <article
            v-for="record in contact_records"
            :id="record.__dom_id"
            :key="record.id"
            class="grid gap-3 border-b border-base-300/70 px-4 py-4 transition-colors hover:bg-primary/[0.035] lg:grid-cols-[minmax(15rem,1.25fr)_minmax(10rem,0.7fr)_minmax(12rem,0.9fr)_auto] lg:items-center"
            :data-contact-record-kind="record.kind"
            :data-contact-record-state="record.state"
          >
            <div class="min-w-0">
              <div class="flex flex-wrap items-center gap-2">
                <span :class="record.status.class">{{ record.status.label }}</span>
                <span class="font-mono text-[0.62rem] uppercase tracking-[0.14em] text-base-content/45">
                  {{ record.record_kind_label }}
                </span>
              </div>
              <p class="mt-2 truncate font-mono text-xs font-semibold text-base-content/80">
                {{ record.id }}
              </p>
            </div>

            <div>
              <p class="hud-label">Operational window</p>
              <p class="mt-1 font-mono text-xs text-base-content/70">
                {{ record.window.starts_at }}
              </p>
              <p class="mt-0.5 font-mono text-[0.66rem] text-base-content/45">
                to {{ record.window.ends_at }}
              </p>
            </div>

            <div class="min-w-0">
              <p class="hud-label">Intent / source</p>
              <p class="mt-1 truncate text-xs text-base-content/70">{{ record.intent }}</p>
              <p class="mt-0.5 truncate font-mono text-[0.66rem] text-base-content/45">
                {{ record.source_endpoints }}
              </p>
            </div>

            <a
              :id="record.inspect_action.id"
              :href="record.inspect_action.href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="btn btn-sm btn-outline justify-self-start lg:justify-self-end"
            >
              {{ record.inspect_action.label }}
              <span :class="[record.inspect_action.icon, 'h-3.5 w-3.5']"></span>
            </a>
          </article>
        </div>
      </section>

      <div class="mt-5 grid gap-5 lg:grid-cols-[minmax(0,1.45fr)_minmax(22rem,0.75fr)]">
        <div class="min-w-0 space-y-5">
          <section class="border border-base-300 bg-base-200/35 shadow-sm">
            <div class="flex items-center justify-between border-b border-base-300 px-4 py-3">
              <div>
                <p class="hud-label">{{ page.opportunity_search.eyebrow }}</p>
                <p class="mt-1 text-sm text-base-content/60">
                  {{ page.opportunity_search.description }}
                </p>
              </div>
              <span :class="[page.opportunity_search.icon, 'h-5 w-5 text-primary/60']"></span>
            </div>

            <form
              :id="search.id"
              class="grid gap-4 p-4 md:grid-cols-2 xl:grid-cols-4"
              @submit.prevent="submitSearch"
            >
              <div class="fieldset mb-3">
                <label>
                  <span class="hud-label block mb-1.5">{{ search.fields.spacecraft.label }}</span>
                  <select
                    :id="search.fields.spacecraft.id"
                    :name="search.fields.spacecraft.name"
                    :value="formValues.spacecraft_id"
                    class="w-full select"
                    @change="updateField('spacecraft_id', $event)"
                  >
                    <option
                      v-for="option in search.fields.spacecraft.options"
                      :key="option.value"
                      :value="option.value"
                    >
                      {{ option.label }}
                    </option>
                  </select>
                </label>
              </div>

              <div class="fieldset mb-3">
                <label>
                  <span class="hud-label block mb-1.5">{{ search.fields.route.label }}</span>
                  <select
                    :id="search.fields.route.id"
                    :name="search.fields.route.name"
                    :value="formValues.route_key"
                    class="w-full select"
                    @change="updateField('route_key', $event)"
                  >
                    <option
                      v-for="option in search.fields.route.options"
                      :key="option.value"
                      :value="option.value"
                    >
                      {{ option.label }}
                    </option>
                  </select>
                </label>
              </div>

              <div class="fieldset mb-3">
                <label>
                  <span class="hud-label block mb-1.5">{{ search.fields.starts_at.label }}</span>
                  <input
                    :id="search.fields.starts_at.id"
                    :name="search.fields.starts_at.name"
                    type="datetime-local"
                    :value="formValues.starts_at"
                    class="w-full input"
                    @change="updateField('starts_at', $event)"
                  >
                </label>
              </div>

              <div class="fieldset mb-3">
                <label>
                  <span class="hud-label block mb-1.5">{{ search.fields.ends_at.label }}</span>
                  <input
                    :id="search.fields.ends_at.id"
                    :name="search.fields.ends_at.name"
                    type="datetime-local"
                    :value="formValues.ends_at"
                    class="w-full input"
                    @change="updateField('ends_at', $event)"
                  >
                </label>
              </div>

              <div class="flex items-center gap-3 md:col-span-2 xl:col-span-4">
                <button
                  :id="search.submit.id"
                  type="submit"
                  :disabled="search.submit.disabled"
                  class="btn btn-primary btn-sm min-w-40 font-mono text-xs uppercase tracking-wider disabled:opacity-50"
                >
                  {{ search.submit.label }}
                </button>
                <p v-if="search.error" :id="search.error.id" class="text-sm text-error">
                  {{ search.error.message }}
                </p>
              </div>
            </form>

            <div
              v-if="readiness"
              :id="readiness.id"
              class="mx-4 mb-4 border-l-2 border-warning bg-warning/5 px-4 py-3"
            >
              <p class="text-sm font-semibold text-warning">{{ readiness.title }}</p>
              <div class="mt-2 space-y-1 text-xs text-base-content/60">
                <p v-for="(finding, index) in readiness.findings" :key="`${index}-${finding.message}`">
                  {{ finding.message }}
                </p>
              </div>
              <a
                :href="readiness.action.href"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="mt-3 inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
              >
                {{ readiness.action.label }}
                <span :class="[readiness.action.icon, 'h-3 w-3']"></span>
              </a>
            </div>
          </section>

          <section class="border border-base-300 bg-base-200/20">
            <div class="flex items-center justify-between border-b border-base-300 px-4 py-3">
              <div>
                <p class="hud-label">{{ page.opportunities.eyebrow }}</p>
                <p class="mt-1 text-sm text-base-content/60">
                  {{ page.opportunities.description }}
                </p>
              </div>
              <span :id="page.opportunities.count.id" class="font-mono text-sm text-primary">
                {{ page.opportunities.count.value }}
              </span>
            </div>

            <div :id="page.opportunities.rows_id">
              <div
                :id="page.opportunities.empty.id"
                class="hidden only:block px-4 py-12 text-center"
              >
                <span
                  :class="[page.opportunities.empty.icon, 'mx-auto h-6 w-6 text-base-content/30']"
                ></span>
                <p class="mt-3 text-sm text-base-content/55">{{ page.opportunities.empty.copy }}</p>
              </div>
              <article
                v-for="opportunity in opportunities"
                :id="opportunity.__dom_id"
                :key="opportunity.id"
                class="group grid gap-4 border-b border-base-300/70 px-4 py-4 transition-colors hover:bg-primary/[0.035] xl:grid-cols-[minmax(0,1.2fr)_minmax(11rem,0.7fr)_8rem] xl:items-center"
              >
                <div class="min-w-0">
                  <div class="mb-1 flex items-center gap-2">
                    <span class="h-1.5 w-1.5 rounded-full bg-success shadow-[0_0_8px_currentColor]"></span>
                    <span class="font-mono text-[0.65rem] uppercase tracking-[0.18em] text-base-content/50">
                      {{ opportunity.provider }}
                    </span>
                  </div>
                  <p class="truncate text-sm font-semibold text-base-content">
                    {{ opportunity.window.starts_at }} — {{ opportunity.window.ends_at }}
                  </p>
                  <p class="mt-1 truncate font-mono text-[0.68rem] text-base-content/45">
                    {{ opportunity.service_summary }}
                  </p>
                </div>

                <div class="border-l border-base-300/70 pl-4">
                  <p class="hud-label">Delivery / antenna</p>
                  <p class="mt-1 truncate font-mono text-xs text-base-content/70">
                    {{ opportunity.delivery }}
                  </p>
                  <p class="mt-1 truncate font-mono text-[0.65rem] text-base-content/40">
                    {{ opportunity.antenna }}
                  </p>
                </div>

                <button
                  :id="opportunity.reserve_action.id"
                  type="button"
                  :disabled="actionState(opportunity.id, opportunity.reserve_action).disabled"
                  class="btn btn-primary btn-sm w-full font-mono text-[0.7rem] uppercase tracking-wider disabled:opacity-50"
                  @click="reserve(opportunity)"
                >
                  {{ actionState(opportunity.id, opportunity.reserve_action).busy
                    ? opportunity.reserve_action.busy_label
                    : opportunity.reserve_action.label }}
                </button>
              </article>
            </div>
          </section>
        </div>

        <aside class="min-w-0 border border-base-300 bg-base-200/25 lg:sticky lg:top-0 lg:self-start">
          <div class="border-b border-base-300 px-4 py-3">
            <p class="hud-label">{{ page.reservations.eyebrow }}</p>
            <p class="mt-1 text-sm text-base-content/60">{{ page.reservations.description }}</p>
          </div>
          <div :id="page.reservations.rows_id">
            <div
              :id="page.reservations.empty.id"
              class="hidden only:block px-4 py-12 text-center"
            >
              <span
                :class="[page.reservations.empty.icon, 'mx-auto h-6 w-6 text-base-content/30']"
              ></span>
              <p class="mt-3 text-sm text-base-content/55">{{ page.reservations.empty.copy }}</p>
            </div>
            <article
              v-for="reservation in provider_reservations"
              :id="reservation.__dom_id"
              :key="reservation.id"
              class="border-b border-base-300/70 px-4 py-4"
            >
              <div class="flex items-start justify-between gap-3">
                <div class="min-w-0">
                  <div class="flex flex-wrap items-center gap-2">
                    <span :class="reservation.status.class">{{ reservation.status.label }}</span>
                    <span class="font-mono text-[0.62rem] uppercase tracking-wider text-base-content/45">
                      {{ reservation.provider_status }}
                    </span>
                  </div>
                  <p class="mt-2 text-sm font-semibold">
                    {{ reservation.window.starts_at }} — {{ reservation.window.ends_at }}
                  </p>
                  <p class="mt-1 truncate font-mono text-[0.68rem] text-base-content/45">
                    {{ reservation.id }}
                  </p>
                </div>

                <button
                  v-if="reservation.cancel_action"
                  :id="reservation.cancel_action.id"
                  type="button"
                  :data-confirm="reservation.cancel_action.confirm"
                  :disabled="actionState(reservation.id, reservation.cancel_action).disabled"
                  class="btn btn-ghost btn-xs text-error disabled:opacity-50"
                  @click="cancel(reservation)"
                >
                  {{ reservation.cancel_action.label }}
                </button>
              </div>

              <a
                :id="reservation.detail_action.id"
                :href="reservation.detail_action.href"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="mt-3 inline-flex items-center gap-1 font-mono text-[0.66rem] font-semibold uppercase tracking-[0.14em] text-primary hover:underline"
              >
                {{ reservation.detail_action.label }}
                <span :class="[reservation.detail_action.icon, 'h-3 w-3']"></span>
              </a>

              <div class="mt-3 grid grid-cols-3 gap-px border border-base-300/60 bg-base-300/60 text-xs">
                <div
                  v-for="observation in reservation.observations"
                  :id="observation.id"
                  :key="observation.id"
                  class="bg-base-200/70 px-3 py-2"
                >
                  <p class="hud-label">{{ observation.label }}</p>
                  <p class="mt-1 font-mono text-[0.68rem] font-semibold uppercase text-base-content/70">
                    {{ observation.value }}
                  </p>
                </div>
              </div>

              <div class="mt-3 grid gap-3 border-t border-base-300/60 pt-3 text-xs sm:grid-cols-2">
                <div
                  v-for="reference in [reservation.provider, reservation.transport, reservation.service, reservation.delivery]"
                  :id="reference.id"
                  :key="reference.id"
                >
                  <p class="hud-label">{{ reference.label }}</p>
                  <p class="mt-1 truncate text-base-content/70">
                    {{ reference.display }}
                    <span class="font-mono text-base-content/40">v{{ reference.version }}</span>
                  </p>
                </div>
              </div>

              <div v-if="reservation.uncertain" class="mt-3 border-l-2 border-warning/70 pl-3">
                <p class="text-xs text-warning/80">
                  Provider state is uncertain; reconciliation will retry.
                </p>
              </div>

              <div
                v-if="reservation.configuration_failure"
                class="mt-3 border-l-2 border-error/70 bg-error/5 px-3 py-2"
              >
                <p class="text-xs font-semibold text-error">
                  Provider delivery conflicts with approved setup.
                </p>
                <p class="mt-1 text-xs text-base-content/55">
                  The reservation remains durable; Cadence will not use the unapproved descriptor.
                </p>
              </div>

              <details
                v-if="reservation.diagnostics"
                :id="reservation.diagnostics.id"
                class="mt-3 border-t border-base-300/60 pt-3"
              >
                <summary class="cursor-pointer font-mono text-[0.65rem] uppercase tracking-[0.16em] text-base-content/45 hover:text-primary">
                  {{ reservation.diagnostics.title }}
                </summary>
                <dl class="mt-3 grid gap-2 font-mono text-[0.65rem] text-base-content/55">
                  <div v-for="row in reservation.diagnostics.rows" :key="row.label">
                    <dt class="inline text-base-content/35">{{ row.label }} </dt>
                    <dd class="inline">{{ row.value }}</dd>
                  </div>
                </dl>
              </details>
            </article>
          </div>
        </aside>
      </div>
    </div>
  </section>
</template>
