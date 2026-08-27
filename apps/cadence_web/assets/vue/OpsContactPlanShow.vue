<script setup lang="ts">
import {ref, watch} from "vue"
import CadencePanel from "./ui/components/CadencePanel.vue"

type EmptyPayload = Record<string, never>

type ExecuteAction = {
  id: string
  event: "execute-plan"
  payload: EmptyPayload
  label: string
  disabled: boolean
}

type ReasonField = {
  id: string
  name: string
  type: "textarea"
  label: string
  required: boolean
  value: string
}

type ReasonForm = {
  id: string
  field: ReasonField
  action: {
    id: string
    label: string
  }
}

type AdminControls = {
  approve_form: ReasonForm
  rejection: {
    id: string
    summary: string
    form: ReasonForm
  }
}

type Page = {
  id: string
  back_action: {
    label: string
    href: string
  }
  header: {
    state: {
      label: string
      class: string
    }
    version_label: string
    heading: string
    description: string
    execute_action: ExecuteAction | null
  }
  summary: {
    id: string
    coverage: {
      label: string
      class: string
    }
    selected_count: number
    approval_identity: string
    content_hash: {
      id: string
      value: string
    }
  }
  selections: {
    id: string
    empty: {
      id: string
      message: string
    }
  }
  unsatisfied: {
    id: string
    heading: string
    requirements: Array<{
      requirement_label: string
      hard_failures: string[]
    }>
  } | null
  policy: {
    id: string
    summary: string
    selections: Array<{
      contact_opportunity_snapshot_id: string
      route_display_name: string
      policy_summary: string
    }>
  }
  execution: {
    id: string
    heading: string
    description: string
    empty: {
      id: string
      message: string
    }
  }
  submission: {
    heading: string
    description: string
  } | null
  decision: {
    heading: string
    description: string
    admin_required: {
      id: string
      message: string
    } | null
  } | null
  approval_evidence: {
    id: string
    heading: string
    empty: {
      id: string
      message: string
    }
  }
  rationale: {
    heading: string
    value: string
    plan_id: string
  }
}

type SelectedOpportunity = {
  __dom_id: string
  contact_opportunity_snapshot_id: string
  provider_display_name: string
  ground_station_ref: string
  starts_at: string
  duration: string
  expiry: {
    value: string
    class: string
  }
}

type ExecutionItem = {
  __dom_id: string
  contact_plan_execution_item_id: string
  contact_opportunity_snapshot_id: string
  attempt_count: number
  state: {
    label: string
    class: string
  }
  contact_link: {
    label: string
    href: string
  } | null
}

type Approval = {
  __dom_id: string
  contact_plan_approval_id: string
  decision: {
    label: string
    class: string
  }
  version_label: string
  reason: string
  actor_summary: string
}

const props = defineProps<{
  page: Page
  submission_form: ReasonForm | null
  admin_controls: AdminControls | null
  selected_opportunities: SelectedOpportunity[]
  execution_items: ExecutionItem[]
  approvals: Approval[]
}>()

const emit = defineEmits<{
  "submit-plan": [payload: {submission: {reason: string}}]
  "approve-plan": [payload: {decision: {reason: string}}]
  "reject-plan": [payload: {decision: {reason: string}}]
  "execute-plan": [payload: EmptyPayload]
}>()

const normalizeString = (value: unknown): string => (value == null ? "" : String(value))

const submissionReason = ref(normalizeString(props.submission_form?.field.value))
const approvalReason = ref(normalizeString(props.admin_controls?.approve_form.field.value))
const rejectionReason = ref(normalizeString(props.admin_controls?.rejection.form.field.value))

watch(
  () => props.submission_form,
  (serverForm) => {
    submissionReason.value = normalizeString(serverForm?.field.value)
  },
  {deep: true}
)

watch(
  () => props.admin_controls,
  (serverControls) => {
    approvalReason.value = normalizeString(serverControls?.approve_form.field.value)
    rejectionReason.value = normalizeString(serverControls?.rejection.form.field.value)
  },
  {deep: true}
)

const submitPlan = () =>
  emit("submit-plan", {submission: {reason: normalizeString(submissionReason.value)}})

const approvePlan = () =>
  emit("approve-plan", {decision: {reason: normalizeString(approvalReason.value)}})

const rejectPlan = () =>
  emit("reject-plan", {decision: {reason: normalizeString(rejectionReason.value)}})

const executePlan = () => emit("execute-plan", {})
</script>

<template>
  <section :id="page.id" class="h-full overflow-y-auto bg-base-100">
    <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">
      <div class="mx-auto max-w-[96rem]">
        <a
          :href="page.back_action.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="inline-flex items-center gap-1 font-mono text-xs text-base-content/55 hover:text-primary"
        >
          <span class="hero-arrow-left h-3.5 w-3.5"></span>
          {{ page.back_action.label }}
        </a>
        <div class="mt-4 flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
          <div>
            <div class="flex flex-wrap items-center gap-2">
              <span :class="page.header.state.class">{{ page.header.state.label }}</span>
              <span class="font-mono text-[0.65rem] text-base-content/45">
                {{ page.header.version_label }}
              </span>
            </div>
            <h1 class="mt-2 text-2xl font-bold tracking-tight">{{ page.header.heading }}</h1>
            <p class="mt-2 max-w-3xl text-sm text-base-content/60">
              {{ page.header.description }}
            </p>
          </div>
          <button
            v-if="page.header.execute_action !== null"
            :id="page.header.execute_action.id"
            type="button"
            :disabled="page.header.execute_action.disabled"
            class="btn btn-primary btn-sm min-w-40 font-mono text-xs uppercase tracking-wider"
            @click="executePlan"
          >
            {{ page.header.execute_action.label }}
          </button>
        </div>
      </div>
    </header>

    <div
      class="mx-auto grid max-w-[96rem] gap-5 p-5 lg:grid-cols-[minmax(0,1.45fr)_minmax(21rem,0.7fr)] lg:p-7"
    >
      <div class="min-w-0 space-y-5">
        <section :id="page.summary.id" class="border border-base-300 bg-base-200/20">
          <div class="grid gap-4 p-4 sm:grid-cols-3">
            <div>
              <p class="hud-label">Requirement coverage</p>
              <p :class="page.summary.coverage.class">{{ page.summary.coverage.label }}</p>
            </div>
            <div>
              <p class="hud-label">Selected windows</p>
              <p class="mt-1 font-mono text-sm">{{ page.summary.selected_count }}</p>
            </div>
            <div>
              <p class="hud-label">Approval identity</p>
              <p class="mt-1 font-mono text-sm">{{ page.summary.approval_identity }}</p>
            </div>
          </div>
          <div class="border-t border-base-300 px-4 py-3">
            <p class="hud-label">Exact content hash</p>
            <p
              :id="page.summary.content_hash.id"
              class="mt-1 break-all font-mono text-[0.68rem] text-base-content/55"
            >{{ page.summary.content_hash.value }}</p>
          </div>
        </section>

        <CadencePanel class="border border-base-300 bg-base-200/20" header-class="border-b border-base-300 px-4 py-3">
          <template #header>
            <p class="hud-label">Selected provider windows</p>
            <p class="mt-1 text-sm text-base-content/55">
              These immutable snapshots are the only opportunities execution may reserve.
            </p>
          </template>
          <div :id="page.selections.id">
            <div
              :id="page.selections.empty.id"
              class="hidden only:block px-4 py-10 text-center text-sm text-base-content/50"
            >{{ page.selections.empty.message }}</div>
            <div
              v-for="snapshot in selected_opportunities"
              :id="snapshot.__dom_id"
              :key="snapshot.contact_opportunity_snapshot_id"
              class="grid gap-3 border-b border-base-300 px-4 py-4 last:border-b-0 md:grid-cols-[minmax(0,1.2fr)_repeat(3,minmax(8rem,0.55fr))] md:items-center"
            >
              <div class="min-w-0">
                <p class="truncate text-sm font-semibold">{{ snapshot.provider_display_name }}</p>
                <p class="mt-1 truncate font-mono text-[0.65rem] text-base-content/45">
                  {{ snapshot.ground_station_ref }}
                </p>
              </div>
              <div>
                <p class="hud-label">Starts UTC</p>
                <p class="mt-1 font-mono text-xs">{{ snapshot.starts_at }}</p>
              </div>
              <div>
                <p class="hud-label">Duration</p>
                <p class="mt-1 font-mono text-xs">{{ snapshot.duration }}</p>
              </div>
              <div>
                <p class="hud-label">Opportunity expires</p>
                <p :class="snapshot.expiry.class">{{ snapshot.expiry.value }}</p>
              </div>
            </div>
          </div>
        </CadencePanel>

        <CadencePanel
          v-if="page.unsatisfied !== null"
          :id="page.unsatisfied.id"
          class="border border-warning/40 bg-warning/5"
          header-class="border-b border-warning/30 px-4 py-3"
        >
          <template #header>
            <p class="hud-label text-warning">{{ page.unsatisfied.heading }}</p>
          </template>
          <div class="space-y-3 p-4">
            <div
              v-for="requirement in page.unsatisfied.requirements"
              :key="requirement.requirement_label"
              class="text-sm"
            >
              <p class="font-mono text-xs text-warning">{{ requirement.requirement_label }}</p>
              <p
                v-for="failure in requirement.hard_failures"
                :key="failure"
                class="mt-1 text-base-content/65"
              >{{ failure }}</p>
            </div>
          </div>
        </CadencePanel>

        <details :id="page.policy.id" class="border border-base-300 bg-base-200/20">
          <summary class="cursor-pointer px-4 py-3 text-sm font-semibold">
            {{ page.policy.summary }}
          </summary>
          <div class="border-t border-base-300 p-4">
            <div
              v-for="selection in page.policy.selections"
              :key="selection.contact_opportunity_snapshot_id"
              class="mb-4 border-l-2 border-primary/30 pl-3 last:mb-0"
            >
              <p class="font-mono text-[0.65rem] text-base-content/45">
                {{ selection.contact_opportunity_snapshot_id }}
              </p>
              <p class="mt-1 text-sm">{{ selection.route_display_name }}</p>
              <p class="mt-1 text-xs text-base-content/55">{{ selection.policy_summary }}</p>
            </div>
          </div>
        </details>

        <CadencePanel class="border border-base-300 bg-base-200/20" header-class="border-b border-base-300 px-4 py-3">
          <template #header>
            <p class="hud-label">{{ page.execution.heading }}</p>
            <p class="mt-1 text-sm text-base-content/55">{{ page.execution.description }}</p>
          </template>
          <div :id="page.execution.id">
            <div
              :id="page.execution.empty.id"
              class="hidden only:block px-4 py-10 text-center text-sm text-base-content/50"
            >{{ page.execution.empty.message }}</div>
            <div
              v-for="item in execution_items"
              :id="item.__dom_id"
              :key="item.contact_plan_execution_item_id"
              class="flex items-center justify-between gap-4 border-b border-base-300 px-4 py-3 last:border-b-0"
            >
              <div class="min-w-0">
                <p class="truncate font-mono text-xs">
                  {{ item.contact_opportunity_snapshot_id }}
                </p>
                <p class="mt-1 font-mono text-[0.6rem] text-base-content/40">
                  attempts {{ item.attempt_count }}
                </p>
              </div>
              <div class="flex items-center gap-3">
                <span :class="item.state.class">{{ item.state.label }}</span>
                <a
                  v-if="item.contact_link !== null"
                  :href="item.contact_link.href"
                  data-phx-link="redirect"
                  data-phx-link-state="push"
                  class="text-xs text-primary hover:underline"
                >{{ item.contact_link.label }}</a>
              </div>
            </div>
          </div>
        </CadencePanel>
      </div>

      <aside class="min-w-0 space-y-5">
        <section
          v-if="page.submission !== null && submission_form !== null"
          class="border border-base-300 bg-base-200/20 p-4"
        >
          <p class="hud-label">{{ page.submission.heading }}</p>
          <p class="mt-2 text-sm text-base-content/55">{{ page.submission.description }}</p>
          <form :id="submission_form.id" class="mt-4" @submit.prevent="submitPlan">
            <div class="fieldset mb-3">
              <label :for="submission_form.field.id">
                <span class="hud-label block mb-1.5">{{ submission_form.field.label }}</span>
                <textarea
                  :id="submission_form.field.id"
                  v-model="submissionReason"
                  :name="submission_form.field.name"
                  :required="submission_form.field.required"
                  class="w-full textarea"
                ></textarea>
              </label>
            </div>
            <button
              :id="submission_form.action.id"
              type="submit"
              class="btn btn-primary btn-sm w-full font-mono text-xs uppercase tracking-wider"
            >{{ submission_form.action.label }}</button>
          </form>
        </section>

        <section
          v-if="page.decision !== null"
          class="border border-primary/35 bg-primary/[0.04] p-4"
        >
          <p class="hud-label">{{ page.decision.heading }}</p>
          <p class="mt-2 text-sm text-base-content/55">{{ page.decision.description }}</p>
          <template v-if="admin_controls !== null">
            <form
              :id="admin_controls.approve_form.id"
              class="mt-4"
              @submit.prevent="approvePlan"
            >
              <div class="fieldset mb-3">
                <label :for="admin_controls.approve_form.field.id">
                  <span class="hud-label block mb-1.5">
                    {{ admin_controls.approve_form.field.label }}
                  </span>
                  <textarea
                    :id="admin_controls.approve_form.field.id"
                    v-model="approvalReason"
                    :name="admin_controls.approve_form.field.name"
                    :required="admin_controls.approve_form.field.required"
                    class="w-full textarea"
                  ></textarea>
                </label>
              </div>
              <button
                :id="admin_controls.approve_form.action.id"
                type="submit"
                class="btn btn-primary btn-sm w-full"
              >{{ admin_controls.approve_form.action.label }}</button>
            </form>
            <details
              :id="admin_controls.rejection.id"
              class="mt-3 border-t border-base-300 pt-3"
            >
              <summary class="cursor-pointer text-xs text-error">
                {{ admin_controls.rejection.summary }}
              </summary>
              <form
                :id="admin_controls.rejection.form.id"
                class="mt-3"
                @submit.prevent="rejectPlan"
              >
                <div class="fieldset mb-3">
                  <label :for="admin_controls.rejection.form.field.id">
                    <span class="hud-label block mb-1.5">
                      {{ admin_controls.rejection.form.field.label }}
                    </span>
                    <textarea
                      :id="admin_controls.rejection.form.field.id"
                      v-model="rejectionReason"
                      :name="admin_controls.rejection.form.field.name"
                      :required="admin_controls.rejection.form.field.required"
                      class="w-full textarea"
                    ></textarea>
                  </label>
                </div>
                <button
                  :id="admin_controls.rejection.form.action.id"
                  type="submit"
                  class="btn btn-ghost btn-sm w-full text-error"
                >{{ admin_controls.rejection.form.action.label }}</button>
              </form>
            </details>
          </template>
          <p
            v-else-if="page.decision.admin_required !== null"
            :id="page.decision.admin_required.id"
            class="mt-4 border-l-2 border-warning px-3 text-xs text-warning"
          >{{ page.decision.admin_required.message }}</p>
        </section>

        <CadencePanel class="border border-base-300 bg-base-200/20" header-class="border-b border-base-300 px-4 py-3">
          <template #header>
            <p class="hud-label">{{ page.approval_evidence.heading }}</p>
          </template>
          <div :id="page.approval_evidence.id">
            <div
              :id="page.approval_evidence.empty.id"
              class="hidden only:block px-4 py-8 text-center text-sm text-base-content/50"
            >{{ page.approval_evidence.empty.message }}</div>
            <div
              v-for="approval in approvals"
              :id="approval.__dom_id"
              :key="approval.contact_plan_approval_id"
              class="border-b border-base-300 p-4 last:border-b-0"
            >
              <div class="flex items-center justify-between">
                <span :class="approval.decision.class">{{ approval.decision.label }}</span>
                <span class="font-mono text-[0.65rem] text-base-content/45">
                  {{ approval.version_label }}
                </span>
              </div>
              <p class="mt-2 text-sm text-base-content/60">{{ approval.reason }}</p>
              <p class="mt-2 font-mono text-[0.65rem] text-base-content/40">
                {{ approval.actor_summary }}
              </p>
            </div>
          </div>
        </CadencePanel>

        <section class="border border-base-300 bg-base-200/20 p-4">
          <p class="hud-label">{{ page.rationale.heading }}</p>
          <p class="mt-2 text-sm text-base-content/60">{{ page.rationale.value }}</p>
          <p class="mt-3 font-mono text-[0.6rem] text-base-content/35">
            {{ page.rationale.plan_id }}
          </p>
        </section>
      </aside>
    </div>
  </section>
</template>
