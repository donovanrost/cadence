<script setup lang="ts">
import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"
import CadenceField from "./ui/components/CadenceField.vue"
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"
import {reactive, watch} from "vue"
import CadencePanel from "./ui/components/CadencePanel.vue"

type EmptyPayload = Record<string, never>

type ResultState = {
  state: string
  label: string
  class: string
}

type RequirementRow = {
  id: string
  __dom_id: string
  spacecraft_id: string
  contact_requirement_id: string
  contact_requirement_version: number
  requirement_href: string
  input: ResultState
  coverage: ResultState
  contact_planning_run_id: string
}

type ExceptionRow = {
  id: string
  __dom_id: string
  contact_requirement_id: string
  result: {
    state: string
    label: string
  }
}

type DecisionRow = {
  id: string
  __dom_id: string
  fleet_planning_decision_id: string
  disposition: ResultState
  title: string | null
  contact_opportunity_snapshot_id: string
  score: number
  operational_rationale: string | null
  hard_constraints: string
}

type HorizonCommitment = {
  id: string
  __dom_id: string
  fleet_planning_decision_id: string
  spacecraft_id: string
  starts_at: string
  duration_seconds: number
  disposition: "locked" | "selected"
}

type ResourcePressure = {
  id: string
  __dom_id: string
  peak_parallel: number
  capacity: number
  over_capacity: boolean
  pressure_percent: number
}

type AutomationAction = {
  id: string
  __dom_id: string
  fleet_automation_action_id: string
  action: string
  lifecycle: ResultState
}

type RepairField = {
  id: string
  name: string
  type: "datetime-local"
  label: string
  required: boolean
  value: string
}

type RepairForm = {
  panel_id: string
  id: string
  sync_key: string
  label: string
  copy: string
  fields: {
    horizon_start: RepairField
    horizon_end: RepairField
  }
  submit: {
    id: string
    label: string
  }
}

type RepairValues = {
  horizon_start: string
  horizon_end: string
}

const props = defineProps<{
  page: {
    id: string
    back: {
      href: string
      icon: string
      label: string
    }
    header: {
      lifecycle: ResultState
      algorithm: string
      title: string
      run_id: string
      refresh: {
        id: string
        icon: string
        label: string
        payload: EmptyPayload
      }
      candidate_plan: {
        id: string
        href: string
        label: string
        icon: string
      } | null
    }
    phase_strip: {
      id: string
      phases: Array<{
        index: string
        state: string
        label: string
        complete: boolean
        current: boolean
      }>
    }
    horizon: {
      id: string
      label: string
      range: string
      counts: string
      list_id: string
      empty: {
        id: string
        copy: string
      }
    }
    coverage: {
      id: string
      columns: string[]
      list_id: string
      empty: {
        id: string
        copy: string
      }
    }
    decision_inspector: {
      id: string
      label: string
      copy: string
      count: number
      list_id: string
      empty: {
        id: string
        copy: string
      }
    }
    exception_queue: {
      visible: boolean
      id: string
      label: string
      list_id: string
      empty_id: string
    }
    resource_pressure: {
      id: string
      label: string
      list_id: string
      empty: {
        id: string
        copy: string
      }
    }
    automation: {
      visible: boolean
      label: string
      list_id: string
      empty_id: string
    }
    failure: {
      id: string
      label: string
      reason: string
      phase: string | null
    } | null
  }
  repair_form: RepairForm | null
  planning: boolean
  requirement_rows: RequirementRow[]
  exceptions: ExceptionRow[]
  decisions: DecisionRow[]
  horizon_commitments: HorizonCommitment[]
  resource_pressure: ResourcePressure[]
  automation_actions: AutomationAction[]
}>()

const emit = defineEmits<{
  "refresh-fleet-run": [payload: EmptyPayload]
  "repair-fleet-run": [payload: {repair: RepairValues}]
}>()

const valuesFromRepairForm = (form: RepairForm | null): RepairValues => ({
  horizon_start: form?.fields.horizon_start.value ?? "",
  horizon_end: form?.fields.horizon_end.value ?? ""
})

const repair = reactive<RepairValues>(valuesFromRepairForm(props.repair_form))
let acceptedServerValues = valuesFromRepairForm(props.repair_form)
let acceptedSyncKey = props.repair_form?.sync_key ?? null

const repairValues = (): RepairValues => ({
  horizon_start: repair.horizon_start,
  horizon_end: repair.horizon_end
})

const sameRepairValues = (left: RepairValues, right: RepairValues) =>
  left.horizon_start === right.horizon_start && left.horizon_end === right.horizon_end

watch(
  () => props.repair_form,
  (serverForm) => {
    if (!serverForm) return

    const serverValues = valuesFromRepairForm(serverForm)
    const localValues = repairValues()
    const localIsPristine = sameRepairValues(localValues, acceptedServerValues)
    const runChanged = serverForm.sync_key !== acceptedSyncKey

    acceptedServerValues = serverValues
    acceptedSyncKey = serverForm.sync_key

    if (localIsPristine || runChanged) Object.assign(repair, serverValues)
  },
  {deep: true}
)

const refreshFleetRun = () => emit("refresh-fleet-run", props.page.header.refresh.payload)

const repairFleetRun = () => {
  emit("repair-fleet-run", {repair: repairValues()})
}
</script>

<template>
  <section
    :id="page.id"
    :aria-busy="planning"
    class="h-full overflow-y-auto bg-base-100"
  >
    <CadencePageHeaderFrame variant="ops">
      <div class="mx-auto max-w-[110rem]">
        <a
          :href="page.back.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="inline-flex items-center gap-1 font-mono text-xs text-base-content/55 hover:text-primary"
        >
          <span :class="[page.back.icon, 'h-3.5 w-3.5']"></span>
          {{ page.back.label }}
        </a>
        <div class="mt-4 flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <div class="flex flex-wrap items-center gap-2">
              <span :class="page.header.lifecycle.class">
                {{ page.header.lifecycle.label }}
              </span>
              <span class="font-mono text-[0.65rem] uppercase text-base-content/45">
                {{ page.header.algorithm }}
              </span>
            </div>
            <h1 class="mt-2 text-2xl font-bold tracking-tight">
              {{ page.header.title }}
            </h1>
            <p class="mt-2 font-mono text-[0.65rem] text-base-content/45">
              {{ page.header.run_id }}
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <button
              :id="page.header.refresh.id"
              type="button"
              class="btn btn-ghost btn-sm gap-2"
              @click="refreshFleetRun"
            >
              <span :class="[page.header.refresh.icon, 'h-4 w-4']"></span>
              {{ page.header.refresh.label }}
            </button>
            <a
              v-if="page.header.candidate_plan"
              :id="page.header.candidate_plan.id"
              :href="page.header.candidate_plan.href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="btn btn-primary btn-sm gap-2"
            >
              {{ page.header.candidate_plan.label }}
              <span :class="[page.header.candidate_plan.icon, 'h-4 w-4']"></span>
            </a>
          </div>
        </div>
      </div>
    </CadencePageHeaderFrame>

    <div class="mx-auto max-w-[110rem] space-y-5 p-5 lg:p-7">
      <section
        :id="page.phase_strip.id"
        class="grid border border-base-300 bg-base-200/20 sm:grid-cols-3 xl:grid-cols-6"
      >
        <div
          v-for="phase in page.phase_strip.phases"
          :key="phase.state"
          :class="[
            'border-b border-base-300 px-3 py-3 last:border-b-0 sm:border-r xl:border-b-0 xl:last:border-r-0',
            phase.current && 'bg-primary/[0.07]',
            phase.complete && 'text-base-content/65',
            !phase.current && !phase.complete && 'text-base-content/35'
          ]"
        >
          <p class="font-mono text-[0.56rem] tracking-[0.16em] text-primary/60">
            {{ phase.index }}
          </p>
          <p class="mt-1 text-xs font-semibold">{{ phase.label }}</p>
        </div>
      </section>

      <CadencePanel :id="page.horizon.id" class="border border-base-300 bg-base-200/15" header-class="grid gap-3 border-b border-base-300 px-4 py-3 md:grid-cols-[1fr_auto] md:items-end">
        <template #header>
          <div>
            <p class="hud-label">{{ page.horizon.label }}</p>
            <p class="mt-1 font-mono text-xs tabular-nums">
              {{ page.horizon.range }}
            </p>
          </div>
          <p class="font-mono text-[0.65rem] text-base-content/45">
            {{ page.horizon.counts }}
          </p>
        </template>
        <div class="relative min-h-28 overflow-x-auto px-4 py-5">
          <div class="absolute left-4 right-4 top-1/2 h-px bg-base-300"></div>
          <div
            :id="page.horizon.list_id"
            class="relative flex min-w-max items-center gap-2"
          >
            <div
              :id="page.horizon.empty.id"
              class="hidden only:block px-4 py-8 text-sm text-base-content/50"
            >
              {{ page.horizon.empty.copy }}
            </div>
            <div
              v-for="commitment in horizon_commitments"
              :id="commitment.__dom_id"
              :key="commitment.fleet_planning_decision_id"
              :class="[
                'relative min-w-52 border px-3 py-3',
                commitment.disposition === 'locked' && 'border-info/40 bg-info/[0.07]',
                commitment.disposition === 'selected' && 'border-primary/40 bg-primary/[0.06]'
              ]"
            >
              <p class="truncate text-xs font-semibold">
                {{ commitment.spacecraft_id }}
              </p>
              <p class="mt-1 font-mono text-[0.62rem] text-base-content/50">
                {{ commitment.starts_at }} · {{ commitment.duration_seconds }} sec
              </p>
              <span class="mt-2 inline-block font-mono text-[0.58rem] uppercase text-primary/75">
                {{ commitment.disposition }}
              </span>
            </div>
          </div>
        </div>
      </CadencePanel>

      <div class="grid gap-5 xl:grid-cols-[minmax(0,1.5fr)_minmax(23rem,0.65fr)]">
        <div class="min-w-0 space-y-5">
          <CadencePanel :id="page.coverage.id" class="border border-base-300 bg-base-200/15" header-class="grid grid-cols-[minmax(12rem,1fr)_7rem_7rem_8rem] border-b border-base-300 px-4 py-2 font-mono text-[0.58rem] uppercase tracking-wider text-base-content/45">
            <template #header>
              <span v-for="column in page.coverage.columns" :key="column">
                {{ column }}
              </span>
            </template>
            <div :id="page.coverage.list_id">
              <div
                :id="page.coverage.empty.id"
                class="hidden only:block px-4 py-10 text-center text-sm text-base-content/50"
              >
                {{ page.coverage.empty.copy }}
              </div>
              <div
                v-for="requirement in requirement_rows"
                :id="requirement.__dom_id"
                :key="requirement.id"
                class="grid grid-cols-[minmax(12rem,1fr)_7rem_7rem_8rem] items-center border-b border-base-300 px-4 py-3 text-xs last:border-b-0"
              >
                <div class="min-w-0">
                  <p class="truncate font-semibold">{{ requirement.spacecraft_id }}</p>
                  <a
                    :href="requirement.requirement_href"
                    data-phx-link="redirect"
                    data-phx-link-state="push"
                    class="mt-1 block truncate font-mono text-[0.6rem] text-primary/70 hover:underline"
                  >
                    {{ requirement.contact_requirement_id }} v{{ requirement.contact_requirement_version }}
                  </a>
                </div>
                <span :class="requirement.input.class">{{ requirement.input.label }}</span>
                <span :class="requirement.coverage.class">
                  {{ requirement.coverage.label }}
                </span>
                <span class="truncate font-mono text-[0.58rem] text-base-content/40">
                  {{ requirement.contact_planning_run_id }}
                </span>
              </div>
            </div>
          </CadencePanel>

          <CadencePanel
            :id="page.decision_inspector.id"
            class="border border-base-300 bg-base-200/15"
            header-class="flex items-end justify-between border-b border-base-300 px-4 py-3"
          >
            <template #header>
              <div>
                <p class="hud-label">{{ page.decision_inspector.label }}</p>
                <p class="mt-1 text-sm text-base-content/55">
                  {{ page.decision_inspector.copy }}
                </p>
              </div>
              <span class="font-mono text-xs text-base-content/45">
                {{ page.decision_inspector.count }}
              </span>
            </template>
            <div :id="page.decision_inspector.list_id">
              <div
                :id="page.decision_inspector.empty.id"
                class="hidden only:block px-4 py-12 text-center text-sm text-base-content/50"
              >
                {{ page.decision_inspector.empty.copy }}
              </div>
              <CadenceDetailsFrame
                v-for="decision in decisions"
                :id="decision.__dom_id"
                :key="decision.fleet_planning_decision_id"
                class="border-b border-base-300 last:border-b-0"
              >
                <summary class="grid cursor-pointer gap-3 px-4 py-3 md:grid-cols-[7rem_minmax(0,1fr)_6rem] md:items-center">
                  <span :class="decision.disposition.class">
                    {{ decision.disposition.label }}
                  </span>
                  <span class="min-w-0">
                    <span class="block truncate text-xs font-semibold">
                      {{ decision.title }}
                    </span>
                    <span class="mt-0.5 block truncate font-mono text-[0.58rem] text-base-content/40">
                      {{ decision.contact_opportunity_snapshot_id }}
                    </span>
                  </span>
                  <span class="text-right font-mono text-xs tabular-nums">
                    {{ decision.score }}
                  </span>
                </summary>
                <div class="grid gap-4 border-t border-base-300 bg-base-200/25 px-4 py-4 md:grid-cols-2">
                  <div>
                    <p class="hud-label">Operational rationale</p>
                    <p class="mt-2 text-sm text-base-content/65">
                      {{ decision.operational_rationale }}
                    </p>
                  </div>
                  <div>
                    <p class="hud-label">Hard constraints</p>
                    <p class="mt-2 text-sm text-base-content/65">
                      {{ decision.hard_constraints }}
                    </p>
                  </div>
                </div>
              </CadenceDetailsFrame>
            </div>
          </CadencePanel>
        </div>

        <aside class="min-w-0 space-y-5">
          <CadencePanel
            v-if="page.exception_queue.visible"
            :id="page.exception_queue.id"
            class="border border-warning/35 bg-warning/[0.035]"
            header-class="border-b border-warning/25 px-4 py-3"
          >
            <template #header>
              <p class="hud-label text-warning">{{ page.exception_queue.label }}</p>
            </template>
            <div :id="page.exception_queue.list_id">
              <div :id="page.exception_queue.empty_id" class="hidden only:block"></div>
              <div
                v-for="exception in exceptions"
                :id="exception.__dom_id"
                :key="exception.id"
                class="border-b border-warning/20 px-4 py-3 last:border-b-0"
              >
                <p class="truncate font-mono text-[0.62rem] text-warning">
                  {{ exception.contact_requirement_id }}
                </p>
                <p class="mt-1 text-xs text-base-content/60">
                  {{ exception.result.label }}
                </p>
              </div>
            </div>
          </CadencePanel>

          <CadencePanel
            :id="page.resource_pressure.id"
            class="border border-base-300 bg-base-200/15"
            header-class="border-b border-base-300 px-4 py-3"
          >
            <template #header>
              <p class="hud-label">{{ page.resource_pressure.label }}</p>
            </template>
            <div :id="page.resource_pressure.list_id">
              <div
                :id="page.resource_pressure.empty.id"
                class="hidden only:block px-4 py-8 text-center text-sm text-base-content/50"
              >
                {{ page.resource_pressure.empty.copy }}
              </div>
              <div
                v-for="resource in resource_pressure"
                :id="resource.__dom_id"
                :key="resource.id"
                class="border-b border-base-300 px-4 py-3 last:border-b-0"
              >
                <div class="flex items-center justify-between gap-3">
                  <p class="truncate font-mono text-[0.6rem]">{{ resource.id }}</p>
                  <span
                    :class="[
                      'font-mono text-xs',
                      resource.over_capacity && 'text-error',
                      !resource.over_capacity && 'text-base-content/55'
                    ]"
                  >
                    {{ resource.peak_parallel }}/{{ resource.capacity }}
                  </span>
                </div>
                <div class="mt-2 h-1 overflow-hidden bg-base-300">
                  <div
                    :class="[
                      'h-full',
                      resource.over_capacity && 'bg-error',
                      !resource.over_capacity && 'bg-primary/60'
                    ]"
                    :style="{width: `${resource.pressure_percent}%`}"
                  ></div>
                </div>
              </div>
            </div>
          </CadencePanel>

          <CadencePanel
            v-if="page.automation.visible"
            class="border border-base-300 bg-base-200/15"
            header-class="border-b border-base-300 px-4 py-3"
          >
            <template #header>
              <p class="hud-label">{{ page.automation.label }}</p>
            </template>
            <div :id="page.automation.list_id">
              <div :id="page.automation.empty_id" class="hidden only:block"></div>
              <div
                v-for="action in automation_actions"
                :id="action.__dom_id"
                :key="action.fleet_automation_action_id"
                class="flex items-center justify-between border-b border-base-300 px-4 py-3 last:border-b-0"
              >
                <span class="font-mono text-xs uppercase">{{ action.action }}</span>
                <span :class="action.lifecycle.class">{{ action.lifecycle.label }}</span>
              </div>
            </div>
          </CadencePanel>

          <section
            v-if="repair_form"
            :id="repair_form.panel_id"
            class="border border-info/35 bg-info/[0.035] p-4"
          >
            <p class="hud-label text-info">{{ repair_form.label }}</p>
            <p class="mt-2 text-sm text-base-content/60">
              {{ repair_form.copy }}
            </p>
            <form
              :id="repair_form.id"
              class="mt-4 space-y-3"
              @submit.prevent="repairFleetRun"
            >
              <CadenceField
                :control-id="repair_form.fields.horizon_start.id"
                wrapper-class="fieldset mb-3"
                :label="repair_form.fields.horizon_start.label"
                label-class="hud-label block mb-1.5"
              >
                <input
                  :id="repair_form.fields.horizon_start.id"
                  v-model="repair.horizon_start"
                  :name="repair_form.fields.horizon_start.name"
                  :type="repair_form.fields.horizon_start.type"
                  :required="repair_form.fields.horizon_start.required"
                  class="w-full input"
                >
              </CadenceField>
              <CadenceField
                :control-id="repair_form.fields.horizon_end.id"
                wrapper-class="fieldset mb-3"
                :label="repair_form.fields.horizon_end.label"
                label-class="hud-label block mb-1.5"
              >
                <input
                  :id="repair_form.fields.horizon_end.id"
                  v-model="repair.horizon_end"
                  :name="repair_form.fields.horizon_end.name"
                  :type="repair_form.fields.horizon_end.type"
                  :required="repair_form.fields.horizon_end.required"
                  class="w-full input"
                >
              </CadenceField>
              <button
                :id="repair_form.submit.id"
                type="submit"
                class="btn btn-info btn-sm w-full"
              >
                {{ repair_form.submit.label }}
              </button>
            </form>
          </section>

          <section
            v-if="page.failure"
            :id="page.failure.id"
            class="border border-error/35 bg-error/[0.035] p-4"
          >
            <p class="hud-label text-error">{{ page.failure.label }}</p>
            <p class="mt-2 text-sm text-base-content/65">
              {{ page.failure.reason }}
            </p>
            <p class="mt-2 font-mono text-[0.6rem] text-base-content/40">
              phase {{ page.failure.phase }}
            </p>
          </section>
        </aside>
      </div>
    </div>
  </section>
</template>
