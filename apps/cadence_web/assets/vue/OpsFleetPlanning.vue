<script setup lang="ts">
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"
import CadencePanel from "./ui/components/CadencePanel.vue"

type ControlTone = "warning" | "muted" | "quiet"
type CoverageTone = "warning" | "quiet"

type HeaderAction = {
  id: string
  icon: string
  label: string
}

type NavigationAction = HeaderAction & {
  href: string
}

type FleetRun = {
  id: string
  __dom_id: string
  fleet_planning_run_id: string
  href: string
  lifecycle: {
    state: string
    label: string
    tone: "error" | "warning" | "primary" | "muted"
    class: string
  }
  trigger: {
    kind: string
    label: string
  }
  horizon: {
    label: string
    start: string
    end: string
    value: string
  }
  phase: {
    state: string
    width_class: string
  }
  coverage: {
    label: string
    value: string
    shortfall: boolean
    tone: CoverageTone
  }
  open_icon: string
}

defineProps<{
  page: {
    id: string
    header: {
      eyebrow: string
      title: string
      copy: string
    }
  }
  actions: {
    refresh: HeaderAction
    policy: NavigationAction
    new_run: NavigationAction
  }
  control_metrics: Array<{
    id: string
    label: string
    value: string
    detail: string
    tone: ControlTone
  }>
  stopped_policy: {
    id: string
    eyebrow: string
    title: string
    copy: string
    action: {
      id: string
      href: string
      label: string
    }
  } | null
  ledger: {
    eyebrow: string
    copy: string
    count: number
    count_label: string
    runs_id: string
    stream_empty_id: string
    empty: {
      id: string
      icon: string
      title: string
      copy: string
    } | null
  }
  journey: {
    id: string
    eyebrow: string
    steps: Array<{
      id: string
      number: string
      label: string
      detail: string
    }>
  }
  recurring_demand: {
    id: string
    eyebrow: string
    copy: string
    action: NavigationAction
  }
  fleet_runs: FleetRun[]
}>()

const emit = defineEmits<{
  "refresh-planning": []
}>()

const controlToneClasses: Record<ControlTone, string> = {
  warning: "text-warning",
  muted: "text-base-content/45",
  quiet: "text-base-content/85"
}

const coverageToneClasses: Record<CoverageTone, string> = {
  warning: "text-warning",
  quiet: "text-base-content/75"
}
</script>

<template>
  <section :id="page.id" class="h-full overflow-y-auto bg-base-100">
    <CadencePageHeaderFrame variant="ops">
      <div class="mx-auto flex max-w-[100rem] flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <p class="font-mono text-[0.65rem] uppercase tracking-[0.28em] text-primary/70">
            {{ page.header.eyebrow }}
          </p>
          <h1 class="mt-1 text-2xl font-bold tracking-tight">{{ page.header.title }}</h1>
          <p class="mt-2 max-w-3xl text-sm text-base-content/60">
            {{ page.header.copy }}
          </p>
        </div>
        <div class="flex flex-wrap gap-2">
          <button
            :id="actions.refresh.id"
            type="button"
            class="btn btn-ghost btn-sm gap-2 font-mono text-xs uppercase tracking-wider"
            @click="emit('refresh-planning')"
          >
            <span :class="[actions.refresh.icon, 'h-4 w-4']"></span>
            {{ actions.refresh.label }}
          </button>
          <a
            :id="actions.policy.id"
            :href="actions.policy.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="btn btn-ghost btn-sm gap-2 font-mono text-xs uppercase tracking-wider"
          >
            <span :class="[actions.policy.icon, 'h-4 w-4']"></span>
            {{ actions.policy.label }}
          </a>
          <a
            :id="actions.new_run.id"
            :href="actions.new_run.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="btn btn-primary btn-sm gap-2 font-mono text-xs uppercase tracking-wider"
          >
            <span :class="[actions.new_run.icon, 'h-4 w-4']"></span>
            {{ actions.new_run.label }}
          </a>
        </div>
      </div>
    </CadencePageHeaderFrame>

    <div class="mx-auto max-w-[100rem] space-y-5 p-5 lg:p-7">
      <CadencePanel
        id="fleet-planning-control-strip"
        class="grid border border-base-300 bg-base-200/20 md:grid-cols-4"
        header-class="border-b border-base-300 px-4 py-4 last:border-b-0 md:border-b-0 md:border-r md:last:border-r-0"
      >
        <template
          v-for="metric in control_metrics"
          :id="metric.id"
          :key="metric.id"
          #header
        >
          <p class="hud-label">{{ metric.label }}</p>
          <p
            :class="[
              'mt-1 font-mono text-lg font-semibold',
              controlToneClasses[metric.tone]
            ]"
          >
            {{ metric.value }}
          </p>
          <p class="mt-0.5 text-xs text-base-content/45">{{ metric.detail }}</p>
        </template>
      </CadencePanel>

      <section
        v-if="stopped_policy"
        :id="stopped_policy.id"
        class="flex flex-col gap-4 border border-warning/35 bg-warning/[0.04] p-5 md:flex-row md:items-center md:justify-between"
      >
        <div>
          <p class="hud-label text-warning">{{ stopped_policy.eyebrow }}</p>
          <h2 class="mt-1 text-base font-semibold">{{ stopped_policy.title }}</h2>
          <p class="mt-1 text-sm text-base-content/55">
            {{ stopped_policy.copy }}
          </p>
        </div>
        <a
          :id="stopped_policy.action.id"
          :href="stopped_policy.action.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-warning btn-sm"
        >
          {{ stopped_policy.action.label }}
        </a>
      </section>

      <div class="grid gap-5 xl:grid-cols-[minmax(0,1.55fr)_minmax(20rem,0.55fr)]">
        <CadencePanel
          class="min-w-0 border border-base-300 bg-base-200/15"
          header-class="flex items-center justify-between border-b border-base-300 px-4 py-3"
        >
          <template #header>
            <div>
              <p class="hud-label">{{ ledger.eyebrow }}</p>
              <p class="mt-1 text-sm text-base-content/55">
                {{ ledger.copy }}
              </p>
            </div>
            <span class="font-mono text-xs text-base-content/45">{{ ledger.count_label }}</span>
          </template>

          <div
            v-if="ledger.empty"
            :id="ledger.empty.id"
            class="px-6 py-16 text-center"
          >
            <span :class="[ledger.empty.icon, 'mx-auto h-8 w-8 text-primary/35']"></span>
            <h2 class="mt-4 text-base font-semibold">{{ ledger.empty.title }}</h2>
            <p class="mx-auto mt-2 max-w-xl text-sm text-base-content/55">
              {{ ledger.empty.copy }}
            </p>
          </div>

          <div :id="ledger.runs_id">
            <div :id="ledger.stream_empty_id" class="hidden only:block"></div>
            <a
              v-for="run in fleet_runs"
              :id="run.__dom_id"
              :key="run.id"
              :href="run.href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="group grid gap-4 border-b border-base-300 px-4 py-4 last:border-b-0 hover:bg-primary/[0.035] md:grid-cols-[minmax(11rem,0.7fr)_minmax(18rem,1.2fr)_minmax(9rem,0.45fr)_auto] md:items-center"
            >
              <div>
                <div class="flex items-center gap-2">
                  <span :class="run.lifecycle.class">
                    {{ run.lifecycle.label }}
                  </span>
                  <span class="font-mono text-[0.6rem] uppercase text-base-content/40">
                    {{ run.trigger.label }}
                  </span>
                </div>
                <p class="mt-2 truncate font-mono text-[0.65rem] text-base-content/45">
                  {{ run.fleet_planning_run_id }}
                </p>
              </div>
              <div>
                <p class="hud-label">{{ run.horizon.label }}</p>
                <p class="mt-1 font-mono text-xs tabular-nums">
                  {{ run.horizon.value }}
                </p>
                <div class="mt-2 h-1 overflow-hidden bg-base-300">
                  <div :class="run.phase.width_class"></div>
                </div>
              </div>
              <div>
                <p class="hud-label">{{ run.coverage.label }}</p>
                <p
                  :class="[
                    'mt-1 text-sm font-semibold',
                    coverageToneClasses[run.coverage.tone]
                  ]"
                >
                  {{ run.coverage.value }}
                </p>
              </div>
              <span
                :class="[
                  run.open_icon,
                  'h-4 w-4 text-base-content/30 group-hover:text-primary'
                ]"
              ></span>
            </a>
          </div>
        </CadencePanel>

        <aside class="space-y-5">
          <CadencePanel
            :id="journey.id"
            class="border border-base-300 bg-base-200/15"
            header-class="border-b border-base-300 px-4 py-3"
          >
            <template #header>
              <p class="hud-label">{{ journey.eyebrow }}</p>
            </template>
            <ol class="divide-y divide-base-300">
              <li
                v-for="step in journey.steps"
                :id="step.id"
                :key="step.number"
                class="grid grid-cols-[2.25rem_1fr] gap-3 px-4 py-3"
              >
                <span class="font-mono text-[0.6rem] tracking-[0.18em] text-primary/60">
                  {{ step.number }}
                </span>
                <div>
                  <p class="text-sm font-semibold">{{ step.label }}</p>
                  <p class="mt-0.5 text-xs text-base-content/45">{{ step.detail }}</p>
                </div>
              </li>
            </ol>
          </CadencePanel>

          <section
            :id="recurring_demand.id"
            class="border border-base-300 bg-base-200/15 p-4"
          >
            <p class="hud-label">{{ recurring_demand.eyebrow }}</p>
            <p class="mt-2 text-sm text-base-content/55">
              {{ recurring_demand.copy }}
            </p>
            <a
              :id="recurring_demand.action.id"
              :href="recurring_demand.action.href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="mt-4 inline-flex items-center gap-1 text-xs font-semibold text-primary hover:underline"
            >
              {{ recurring_demand.action.label }}
              <span :class="[recurring_demand.action.icon, 'h-3.5 w-3.5']"></span>
            </a>
          </section>
        </aside>
      </div>
    </div>
  </section>
</template>
