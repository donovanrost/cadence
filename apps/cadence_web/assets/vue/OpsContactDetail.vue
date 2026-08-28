<script setup lang="ts">
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"
import {reactive, watch} from "vue"
import CadencePanel from "./ui/components/CadencePanel.vue"

type LabelValue = {
  label: string
  value: string
}

type ValueRow = {
  id: string
  label: string
  requested: string
  confirmed: string
  accepted: string
  actual: string
}

type AdminDiagnostics = {
  id: string
  label: string
  rows: LabelValue[]
  link: {
    id: string
    label: string
    href: string
  } | null
}

type Page = {
  id: string
  navigation: {
    id: string
    label: string
    href: string
  }
  header: {
    heading: string
    reservation_id: string
    state: {
      label: string
      class: string
    }
    facts: LabelValue[]
  }
  values: {
    id: string
    eyebrow: string
    heading: string
    copy: string
    columns: string[]
    rows: ValueRow[]
  }
  changes: {
    id: string
    eyebrow: string
    heading: string
    timeline_id: string
    empty: {
      id: string
      copy: string
    }
  }
  audit: {
    eyebrow: string
    heading: string
    timeline_id: string
    empty: {
      id: string
      copy: string
    }
  }
  binding_chain: {
    id: string
    eyebrow: string
    heading: string
    rows: LabelValue[]
  }
  lifecycle: {
    eyebrow: string
    heading: string
    rows: LabelValue[]
  }
  admin_diagnostics?: AdminDiagnostics
}

type DecisionKind = "approval" | "rejection" | "acknowledgment"

type DecisionForm = {
  id: string
  proposal_hash: {
    id: string
    name: string
    value: string
  }
  reason: {
    id: string
    name: string
    label: string
    value: string
    required: boolean
  }
  submit: {
    id: string
    label: string
  }
}

type DecisionForms = {
  approval: DecisionForm | null
  rejection: DecisionForm | null
  acknowledgment: DecisionForm | null
}

type ProviderChange = {
  __dom_id: string
  provider_reservation_change_id: string
  from_provider_revision: string
  provider_revision: string
  lifecycle_state: string
  classification: string
  policy_version: string
  explanation: string
  changed_fields: string[]
  deadline: LabelValue | null
  remediation: {
    id: string
    heading: string
    copy: string
  } | null
  decision_forms?: DecisionForms
}

type ProviderAuditEntry = {
  __dom_id: string
  provider_audit_entry_id: string
  recorded_at: string
  action: string
  outcome: string
  evidence_references: Array<{
    provider_evidence_id: string | null
    content_sha256: string
  }>
}

type DecisionValues = {
  proposal_hash: string
  reason: string
}

const props = defineProps<{
  page: Page
  provider_changes: ProviderChange[]
  provider_audit_entries: ProviderAuditEntry[]
}>()

const emit = defineEmits<{
  "approve-provider-change": [payload: {approval: DecisionValues}]
  "reject-provider-change": [payload: {rejection: DecisionValues}]
  "acknowledge-provider-change": [payload: {acknowledgment: DecisionValues}]
}>()

const decisionReasons = reactive<Record<string, string>>({})
const syncedServerForms = new Map<string, string>()

const reasonKey = (change: ProviderChange, kind: DecisionKind) =>
  `${change.provider_reservation_change_id}:${kind}`

const eachDecisionForm = (
  change: ProviderChange,
  callback: (kind: DecisionKind, form: DecisionForm) => void
) => {
  const forms = change.decision_forms
  if (forms === undefined) return

  if (forms.approval !== null) callback("approval", forms.approval)
  if (forms.rejection !== null) callback("rejection", forms.rejection)
  if (forms.acknowledgment !== null) callback("acknowledgment", forms.acknowledgment)
}

watch(
  () => props.provider_changes,
  (changes) => {
    const activeKeys = new Set<string>()

    for (const change of changes) {
      eachDecisionForm(change, (kind, form) => {
        const key = reasonKey(change, kind)
        const serverVersion = `${form.proposal_hash.value}\u0000${form.reason.value}`
        activeKeys.add(key)

        if (syncedServerForms.get(key) !== serverVersion) {
          decisionReasons[key] = form.reason.value
          syncedServerForms.set(key, serverVersion)
        }
      })
    }

    for (const key of Object.keys(decisionReasons)) {
      if (!activeKeys.has(key)) {
        delete decisionReasons[key]
        syncedServerForms.delete(key)
      }
    }
  },
  {deep: true, immediate: true}
)

const updateReason = (change: ProviderChange, kind: DecisionKind, event: Event) => {
  decisionReasons[reasonKey(change, kind)] = (event.target as HTMLTextAreaElement).value
}

const decisionValues = (
  change: ProviderChange,
  kind: DecisionKind,
  form: DecisionForm
): DecisionValues => ({
  proposal_hash: form.proposal_hash.value,
  reason: decisionReasons[reasonKey(change, kind)] ?? form.reason.value
})

const approve = (change: ProviderChange, form: DecisionForm | null | undefined) => {
  if (form !== null && form !== undefined) {
    emit("approve-provider-change", {approval: decisionValues(change, "approval", form)})
  }
}

const reject = (change: ProviderChange, form: DecisionForm | null | undefined) => {
  if (form !== null && form !== undefined) {
    emit("reject-provider-change", {rejection: decisionValues(change, "rejection", form)})
  }
}

const acknowledge = (change: ProviderChange, form: DecisionForm | null | undefined) => {
  if (form !== null && form !== undefined) {
    emit("acknowledge-provider-change", {
      acknowledgment: decisionValues(change, "acknowledgment", form)
    })
  }
}
</script>

<template>
  <section :id="page.id" class="h-full overflow-y-auto bg-base-100">
    <CadencePageHeaderFrame variant="ops">
      <div
        class="mx-auto flex max-w-[96rem] flex-col gap-4 xl:flex-row xl:items-end xl:justify-between"
      >
        <div class="min-w-0">
          <a
            :id="page.navigation.id"
            :href="page.navigation.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="inline-flex items-center gap-1 font-mono text-[0.65rem] uppercase tracking-[0.18em] text-primary/70 hover:text-primary"
          >
            <span class="hero-arrow-left h-3 w-3"></span>
            {{ page.navigation.label }}
          </a>
          <div class="mt-3 flex flex-wrap items-center gap-3">
            <h1 class="text-2xl font-bold tracking-tight text-base-content">
              {{ page.header.heading }}
            </h1>
            <span
              :class="[
                'border px-2 py-1 font-mono text-[0.62rem] font-bold uppercase tracking-wider',
                page.header.state.class
              ]"
            >{{ page.header.state.label }}</span>
          </div>
          <p class="mt-2 truncate font-mono text-xs text-base-content/50">
            {{ page.header.reservation_id }}
          </p>
        </div>

        <div
          class="grid grid-cols-3 gap-px border border-primary/20 bg-primary/20 font-mono text-xs"
        >
          <div
            v-for="fact in page.header.facts"
            :key="fact.label"
            class="min-w-24 bg-base-200/90 px-3 py-2"
          >
            <p class="text-[0.58rem] uppercase tracking-[0.14em] text-base-content/35">
              {{ fact.label }}
            </p>
            <p class="mt-1 font-semibold text-primary">{{ fact.value }}</p>
          </div>
        </div>
      </div>
    </CadencePageHeaderFrame>

    <div
      class="mx-auto grid max-w-[96rem] gap-5 p-5 xl:grid-cols-[minmax(0,1.5fr)_minmax(20rem,0.62fr)] lg:p-7"
    >
      <main class="min-w-0 space-y-5">
        <CadencePanel :id="page.values.id" class="border border-base-300 bg-base-200/20" header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3">
          <template #header>
            <div>
              <p class="hud-label">{{ page.values.eyebrow }}</p>
              <h2 class="mt-1 text-base font-semibold">{{ page.values.heading }}</h2>
              <p class="mt-1 text-xs text-base-content/55">{{ page.values.copy }}</p>
            </div>
            <span class="hero-table-cells h-5 w-5 text-primary/60"></span>
          </template>

          <div class="overflow-x-auto">
            <table class="w-full min-w-[48rem] table-fixed border-collapse text-left text-xs">
              <thead class="font-mono uppercase tracking-[0.12em] text-base-content/40">
                <tr>
                  <th
                    v-for="(column, index) in page.values.columns"
                    :key="column"
                    :class="[
                      'border-b border-base-300 px-3 py-2',
                      index === 0 && 'w-32',
                      index < page.values.columns.length - 1 && 'border-r'
                    ]"
                  >{{ column }}</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="row in page.values.rows"
                  :id="`contact-value-${row.id}`"
                  :key="row.id"
                >
                  <th
                    class="border-r border-t border-base-300 bg-base-200/60 px-3 py-2 font-mono text-base-content/50"
                  >{{ row.label }}</th>
                  <td
                    class="border-r border-t border-base-300 px-3 py-2 font-mono text-base-content/65 last:border-r-0"
                  >{{ row.requested }}</td>
                  <td
                    class="border-r border-t border-base-300 px-3 py-2 font-mono text-base-content/65 last:border-r-0"
                  >{{ row.confirmed }}</td>
                  <td
                    class="border-r border-t border-base-300 px-3 py-2 font-mono text-base-content/65 last:border-r-0"
                  >{{ row.accepted }}</td>
                  <td class="border-t border-base-300 px-3 py-2 font-mono text-base-content/75">
                    {{ row.actual }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </CadencePanel>

        <CadencePanel :id="page.changes.id" class="border border-base-300 bg-base-200/20" header-class="border-b border-base-300 px-4 py-3">
          <template #header>
            <p class="hud-label">{{ page.changes.eyebrow }}</p>
            <h2 class="mt-1 text-base font-semibold">{{ page.changes.heading }}</h2>
          </template>

          <div :id="page.changes.timeline_id" phx-update="stream">
            <div
              :id="page.changes.empty.id"
              class="hidden only:block px-4 py-10 text-center text-sm text-base-content/50"
            >{{ page.changes.empty.copy }}</div>
            <article
              v-for="change in provider_changes"
              :id="change.__dom_id"
              :key="change.provider_reservation_change_id"
              class="grid gap-4 border-b border-base-300/70 px-4 py-4 lg:grid-cols-[8rem_minmax(0,1fr)]"
            >
              <div>
                <p
                  class="font-mono text-[0.62rem] uppercase tracking-[0.14em] text-base-content/40"
                >Provider revision</p>
                <p class="mt-1 font-mono text-lg font-bold text-primary">
                  {{ change.from_provider_revision }} → {{ change.provider_revision }}
                </p>
                <p
                  class="mt-2 font-mono text-[0.62rem] font-semibold uppercase tracking-[0.12em] text-base-content/55"
                >{{ change.lifecycle_state }}</p>
              </div>

              <div class="min-w-0">
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <p class="text-sm font-semibold">{{ change.classification }}</p>
                  <span class="font-mono text-[0.64rem] text-base-content/40">
                    Policy v{{ change.policy_version }}
                  </span>
                </div>
                <p class="mt-2 text-xs leading-relaxed text-base-content/60">
                  {{ change.explanation }}
                </p>
                <div class="mt-3 flex flex-wrap gap-1.5">
                  <span
                    v-for="field in change.changed_fields"
                    :key="field"
                    class="border border-base-300 bg-base-200 px-2 py-1 font-mono text-[0.62rem] text-base-content/55"
                  >{{ field }}</span>
                </div>

                <div
                  v-if="change.deadline !== null"
                  class="mt-3 border-l-2 border-warning/60 pl-3 text-xs text-warning"
                >{{ change.deadline.label }}: {{ change.deadline.value }}</div>

                <div
                  v-if="change.remediation !== null"
                  :id="change.remediation.id"
                  class="mt-4 border-l-2 border-error bg-error/5 px-3 py-2"
                >
                  <p class="text-xs font-semibold text-error">{{ change.remediation.heading }}</p>
                  <p class="mt-1 text-xs text-base-content/60">{{ change.remediation.copy }}</p>
                </div>

                <div
                  v-if="change.decision_forms?.approval || change.decision_forms?.rejection"
                  class="mt-4 grid gap-3 border-t border-base-300 pt-4 lg:grid-cols-2"
                >
                  <form
                    v-if="change.decision_forms?.approval"
                    :id="change.decision_forms.approval.id"
                    class="space-y-3 border border-success/30 bg-success/5 p-3"
                    @submit.prevent="approve(change, change.decision_forms?.approval)"
                  >
                    <input
                      :id="change.decision_forms.approval.proposal_hash.id"
                      :name="change.decision_forms.approval.proposal_hash.name"
                      type="hidden"
                      :value="change.decision_forms.approval.proposal_hash.value"
                    >
                    <div class="fieldset mb-3">
                      <label :for="change.decision_forms.approval.reason.id">
                        <span class="hud-label block mb-1.5">
                          {{ change.decision_forms.approval.reason.label }}
                        </span>
                        <textarea
                          :id="change.decision_forms.approval.reason.id"
                          :name="change.decision_forms.approval.reason.name"
                          :required="change.decision_forms.approval.reason.required"
                          :value="decisionReasons[reasonKey(change, 'approval')]"
                          class="w-full textarea"
                          @input="updateReason(change, 'approval', $event)"
                        ></textarea>
                      </label>
                    </div>
                    <button
                      :id="change.decision_forms.approval.submit.id"
                      type="submit"
                      class="btn btn-success btn-sm w-full font-mono text-xs uppercase tracking-wider"
                    >{{ change.decision_forms.approval.submit.label }}</button>
                  </form>

                  <form
                    v-if="change.decision_forms?.rejection"
                    :id="change.decision_forms.rejection.id"
                    class="space-y-3 border border-error/30 bg-error/5 p-3"
                    @submit.prevent="reject(change, change.decision_forms?.rejection)"
                  >
                    <input
                      :id="change.decision_forms.rejection.proposal_hash.id"
                      :name="change.decision_forms.rejection.proposal_hash.name"
                      type="hidden"
                      :value="change.decision_forms.rejection.proposal_hash.value"
                    >
                    <div class="fieldset mb-3">
                      <label :for="change.decision_forms.rejection.reason.id">
                        <span class="hud-label block mb-1.5">
                          {{ change.decision_forms.rejection.reason.label }}
                        </span>
                        <textarea
                          :id="change.decision_forms.rejection.reason.id"
                          :name="change.decision_forms.rejection.reason.name"
                          :required="change.decision_forms.rejection.reason.required"
                          :value="decisionReasons[reasonKey(change, 'rejection')]"
                          class="w-full textarea"
                          @input="updateReason(change, 'rejection', $event)"
                        ></textarea>
                      </label>
                    </div>
                    <button
                      :id="change.decision_forms.rejection.submit.id"
                      type="submit"
                      class="btn btn-error btn-outline btn-sm w-full font-mono text-xs uppercase tracking-wider"
                    >{{ change.decision_forms.rejection.submit.label }}</button>
                  </form>
                </div>

                <form
                  v-if="change.decision_forms?.acknowledgment"
                  :id="change.decision_forms.acknowledgment.id"
                  class="mt-4 space-y-3 border border-warning/35 bg-warning/5 p-3"
                  @submit.prevent="acknowledge(change, change.decision_forms?.acknowledgment)"
                >
                  <p class="text-xs font-semibold text-warning">Provider fact is already effective</p>
                  <p class="text-xs text-base-content/60">
                    Acknowledge the fact and record the contingency response. Approval or fictional
                    rejection is unavailable.
                  </p>
                  <input
                    :id="change.decision_forms.acknowledgment.proposal_hash.id"
                    :name="change.decision_forms.acknowledgment.proposal_hash.name"
                    type="hidden"
                    :value="change.decision_forms.acknowledgment.proposal_hash.value"
                  >
                  <div class="fieldset mb-3">
                    <label :for="change.decision_forms.acknowledgment.reason.id">
                      <span class="hud-label block mb-1.5">
                        {{ change.decision_forms.acknowledgment.reason.label }}
                      </span>
                      <textarea
                        :id="change.decision_forms.acknowledgment.reason.id"
                        :name="change.decision_forms.acknowledgment.reason.name"
                        :required="change.decision_forms.acknowledgment.reason.required"
                        :value="decisionReasons[reasonKey(change, 'acknowledgment')]"
                        class="w-full textarea"
                        @input="updateReason(change, 'acknowledgment', $event)"
                      ></textarea>
                    </label>
                  </div>
                  <button
                    :id="change.decision_forms.acknowledgment.submit.id"
                    type="submit"
                    class="btn btn-warning btn-sm font-mono text-xs uppercase tracking-wider"
                  >{{ change.decision_forms.acknowledgment.submit.label }}</button>
                </form>
              </div>
            </article>
          </div>
        </CadencePanel>

        <CadencePanel class="border border-base-300 bg-base-200/20" header-class="border-b border-base-300 px-4 py-3">
          <template #header>
            <p class="hud-label">{{ page.audit.eyebrow }}</p>
            <h2 class="mt-1 text-base font-semibold">{{ page.audit.heading }}</h2>
          </template>
          <ol :id="page.audit.timeline_id" phx-update="stream">
            <li
              :id="page.audit.empty.id"
              class="hidden only:block px-4 py-10 text-center text-sm text-base-content/50"
            >{{ page.audit.empty.copy }}</li>
            <li
              v-for="entry in provider_audit_entries"
              :id="entry.__dom_id"
              :key="entry.provider_audit_entry_id"
              class="grid gap-3 border-b border-base-300/70 px-4 py-4 sm:grid-cols-[9rem_minmax(0,1fr)]"
            >
              <time class="font-mono text-[0.65rem] text-base-content/40">
                {{ entry.recorded_at }}
              </time>
              <div>
                <p class="font-mono text-xs font-semibold text-base-content/75">
                  {{ entry.action }}
                </p>
                <p class="mt-1 text-xs text-base-content/55">Outcome: {{ entry.outcome }}</p>
                <div v-if="entry.evidence_references.length > 0" class="mt-2 space-y-1">
                  <p
                    v-for="reference in entry.evidence_references"
                    :key="`${reference.provider_evidence_id}-${reference.content_sha256}`"
                    class="font-mono text-[0.62rem] text-primary/70"
                  >
                    Evidence {{ reference.provider_evidence_id }} · sha256
                    {{ reference.content_sha256 }}
                  </p>
                </div>
              </div>
            </li>
          </ol>
        </CadencePanel>
      </main>

      <aside class="min-w-0 space-y-5 xl:sticky xl:top-0 xl:self-start">
        <CadencePanel :id="page.binding_chain.id" class="border border-base-300 bg-base-200/25" header-class="border-b border-base-300 px-4 py-3">
          <template #header>
            <p class="hud-label">{{ page.binding_chain.eyebrow }}</p>
            <h2 class="mt-1 text-sm font-semibold">{{ page.binding_chain.heading }}</h2>
          </template>
          <dl class="divide-y divide-base-300/70 text-xs">
            <div v-for="row in page.binding_chain.rows" :key="row.label" class="px-4 py-3">
              <dt class="hud-label">{{ row.label }}</dt>
              <dd class="mt-1 break-all font-mono text-[0.68rem] text-base-content/70">
                {{ row.value }}
              </dd>
            </div>
          </dl>
        </CadencePanel>

        <CadencePanel class="border border-base-300 bg-base-200/25" header-class="border-b border-base-300 px-4 py-3">
          <template #header>
            <p class="hud-label">{{ page.lifecycle.eyebrow }}</p>
            <h2 class="mt-1 text-sm font-semibold">{{ page.lifecycle.heading }}</h2>
          </template>
          <div class="grid grid-cols-2 gap-px bg-base-300/70">
            <div
              v-for="row in page.lifecycle.rows"
              :key="row.label"
              class="bg-base-200/80 px-3 py-3"
            >
              <p class="hud-label">{{ row.label }}</p>
              <p
                class="mt-1 font-mono text-[0.68rem] font-semibold uppercase text-base-content/70"
              >{{ row.value }}</p>
            </div>
          </div>
        </CadencePanel>

        <details
          v-if="page.admin_diagnostics !== undefined"
          :id="page.admin_diagnostics.id"
          class="border border-base-300 bg-base-200/25"
        >
          <summary
            class="cursor-pointer border-b border-base-300 px-4 py-3 font-mono text-[0.68rem] uppercase tracking-[0.16em] text-base-content/55 hover:text-primary"
          >{{ page.admin_diagnostics.label }}</summary>
          <dl class="space-y-3 p-4 font-mono text-[0.65rem] text-base-content/60">
            <div v-for="row in page.admin_diagnostics.rows" :key="row.label">
              <dt class="text-base-content/35">{{ row.label }}</dt>
              <dd class="mt-0.5 break-all">{{ row.value }}</dd>
            </div>
          </dl>
          <a
            v-if="page.admin_diagnostics.link !== null"
            :id="page.admin_diagnostics.link.id"
            :href="page.admin_diagnostics.link.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="mx-4 mb-4 inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
          >
            {{ page.admin_diagnostics.link.label }}
            <span class="hero-arrow-up-right h-3 w-3"></span>
          </a>
        </details>
      </aside>
    </div>
  </section>
</template>
