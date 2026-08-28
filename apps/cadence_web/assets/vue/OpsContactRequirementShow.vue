<script setup lang="ts">
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"
import CadencePanel from "./ui/components/CadencePanel.vue"
import CadenceToggle from "./ui/reka/CadenceToggle.vue"

type EmptyPayload = Record<string, never>

type Action<Payload> = {
  id: string
  event: string
  payload: Payload
  label: string
  disabled: boolean
}

type JourneyStep = {
  label: string
  state: string
  complete: boolean
}

type Page = {
  id: string
  back_action: {
    label: string
    href: string
  }
  header: {
    priority: string
    version_label: string
    intent: string
    outcome: string
    plan_action: Action<EmptyPayload>
  }
  horizon: {
    id: string
    fields: Array<{
      label: string
      value: string
      class: string
    }>
    rationale: string
  }
  planning: {
    heading: string
    description: string
    run_state: {
      id: string
      label: string
    }
    error: {
      id: string
      message: string | null
    }
    searches: {
      id: string
      empty: {
        id: string
        message: string
      }
    }
  }
  opportunities: {
    heading: string
    description: string
    selected_count: {
      id: string
      label: string
    }
    list: {
      id: string
      empty: {
        id: string
        message: string
      }
    }
    footer: string
    create_action: Action<EmptyPayload>
  }
  journey: {
    heading: string
    steps: JourneyStep[]
  }
  versions: {
    heading: string
    id: string
  }
}

type RequirementVersion = {
  __dom_id: string
  contact_requirement_version_id: string
  version_label: string
  created_at: string
  rationale: string
  content_sha256: string
}

type PlanningSearch = {
  __dom_id: string
  contact_planning_search_id: string
  provider_label: string
  route_key: string
  evidence: {
    id: string
    summary: string
  }
  outcome: {
    label: string
    class: string
  }
  opportunity_count: string
}

type Opportunity = {
  __dom_id: string
  contact_opportunity_snapshot_id: string
  provider_display_name: string
  ground_station_ref: string
  starts_at: string
  duration: string
  eligibility: {
    label: string
    class: string
  }
  eligible: boolean
  selected: boolean
  toggle_action: {
    id: string
    event: string
    payload: {
      snapshot_id: string
    }
    disabled: boolean
    aria_label: string
  }
}

const props = defineProps<{
  page: Page
  requirement_versions: RequirementVersion[]
  planning_searches: PlanningSearch[]
  opportunities: Opportunity[]
}>()

const emit = defineEmits<{
  plan: [payload: EmptyPayload]
  "toggle-opportunity": [payload: {snapshot_id: string}]
  "create-plan": [payload: EmptyPayload]
}>()

const plan = () => emit("plan", props.page.header.plan_action.payload)

const toggleOpportunity = (opportunity: Opportunity) => {
  emit("toggle-opportunity", opportunity.toggle_action.payload)
}

const createPlan = () => emit("create-plan", props.page.opportunities.create_action.payload)
</script>

<template>
  <section :id="page.id" class="h-full overflow-y-auto bg-base-100">
    <CadencePageHeaderFrame variant="ops">
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
            <div class="flex items-center gap-2">
              <span class="border border-primary/30 bg-primary/5 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-primary">
                {{ page.header.priority }}
              </span>
              <span class="font-mono text-[0.65rem] text-base-content/45">
                {{ page.header.version_label }}
              </span>
            </div>
            <h1 class="mt-2 text-2xl font-bold tracking-tight">{{ page.header.intent }}</h1>
            <p class="mt-2 max-w-3xl text-sm text-base-content/60">
              {{ page.header.outcome }}
            </p>
          </div>
          <button
            :id="page.header.plan_action.id"
            type="button"
            :disabled="page.header.plan_action.disabled"
            class="btn btn-primary btn-sm min-w-40 font-mono text-xs uppercase tracking-wider"
            @click="plan"
          >
            {{ page.header.plan_action.label }}
          </button>
        </div>
      </div>
    </CadencePageHeaderFrame>

    <div class="mx-auto grid max-w-[96rem] gap-5 p-5 lg:grid-cols-[minmax(0,1.45fr)_minmax(20rem,0.65fr)] lg:p-7">
      <div class="min-w-0 space-y-5">
        <section :id="page.horizon.id" class="border border-base-300 bg-base-200/20">
          <div class="grid gap-4 p-4 sm:grid-cols-3">
            <div v-for="field in page.horizon.fields" :key="field.label">
              <p class="hud-label">{{ field.label }}</p>
              <p :class="field.class">
                {{ field.value }}
              </p>
            </div>
          </div>
          <div class="border-t border-base-300 px-4 py-3 text-sm text-base-content/60">
            {{ page.horizon.rationale }}
          </div>
        </section>

        <CadencePanel class="border border-base-300 bg-base-200/20" header-class="flex items-center justify-between border-b border-base-300 px-4 py-3">
          <template #header>
            <div>
              <p class="hud-label">{{ page.planning.heading }}</p>
              <p class="mt-1 text-sm text-base-content/55">
                {{ page.planning.description }}
              </p>
            </div>
            <span
              :id="page.planning.run_state.id"
              class="font-mono text-xs text-base-content/60"
            >
              {{ page.planning.run_state.label }}
            </span>
          </template>
          <p
            v-if="page.planning.error.message"
            :id="page.planning.error.id"
            class="border-b border-error/30 bg-error/5 px-4 py-3 text-sm text-error"
          >
            {{ page.planning.error.message }}
          </p>
          <div :id="page.planning.searches.id">
            <div
              :id="page.planning.searches.empty.id"
              class="hidden only:block px-4 py-10 text-center text-sm text-base-content/50"
            >
              {{ page.planning.searches.empty.message }}
            </div>
            <div
              v-for="search in planning_searches"
              :id="search.__dom_id"
              :key="search.contact_planning_search_id"
              class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3 last:border-b-0"
            >
              <div class="min-w-0">
                <p class="truncate text-sm font-semibold">{{ search.provider_label }}</p>
                <p class="mt-1 truncate font-mono text-[0.65rem] text-base-content/45">
                  {{ search.route_key }}
                </p>
                <p :id="search.evidence.id" class="mt-1 text-xs text-base-content/55">
                  {{ search.evidence.summary }}
                </p>
              </div>
              <div class="text-right">
                <span :class="search.outcome.class">{{ search.outcome.label }}</span>
                <p class="mt-1 font-mono text-[0.65rem] text-base-content/45">
                  {{ search.opportunity_count }}
                </p>
              </div>
            </div>
          </div>
        </CadencePanel>

        <CadencePanel class="border border-base-300 bg-base-200/20" header-class="flex items-center justify-between border-b border-base-300 px-4 py-3">
          <template #header>
            <div>
              <p class="hud-label">{{ page.opportunities.heading }}</p>
              <p class="mt-1 text-sm text-base-content/55">
                {{ page.opportunities.description }}
              </p>
            </div>
            <span
              :id="page.opportunities.selected_count.id"
              class="font-mono text-sm text-primary"
            >
              {{ page.opportunities.selected_count.label }}
            </span>
          </template>
          <div :id="page.opportunities.list.id">
            <div
              :id="page.opportunities.list.empty.id"
              class="hidden only:block px-4 py-12 text-center text-sm text-base-content/50"
            >
              {{ page.opportunities.list.empty.message }}
            </div>
            <div
              v-for="opportunity in opportunities"
              :id="opportunity.__dom_id"
              :key="opportunity.contact_opportunity_snapshot_id"
              :class="[
                'grid gap-3 border-b border-base-300 px-4 py-4 last:border-b-0 md:grid-cols-[auto_minmax(0,1.2fr)_repeat(3,minmax(7rem,0.55fr))] md:items-center',
                opportunity.selected && 'bg-primary/[0.06]'
              ]"
            >
              <CadenceToggle
                :pressed="opportunity.selected"
                :disabled="opportunity.toggle_action.disabled"
                @request-change="toggleOpportunity(opportunity)"
              >
                <button
                  :id="opportunity.toggle_action.id"
                  type="button"
                  :disabled="opportunity.toggle_action.disabled"
                  :aria-label="opportunity.toggle_action.aria_label"
                  :class="[
                    'h-5 w-5 border text-center font-mono text-xs',
                    opportunity.selected && 'border-primary bg-primary text-primary-content',
                    !opportunity.selected && 'border-base-content/30',
                    !opportunity.eligible && 'cursor-not-allowed opacity-30'
                  ]"
                >
                  {{ opportunity.selected ? "✓" : "" }}
                </button>
              </CadenceToggle>
              <div class="min-w-0">
                <p class="truncate text-sm font-semibold">
                  {{ opportunity.provider_display_name }}
                </p>
                <p class="mt-1 truncate font-mono text-[0.65rem] text-base-content/45">
                  {{ opportunity.ground_station_ref }}
                </p>
              </div>
              <div>
                <p class="hud-label">UTC window</p>
                <p class="mt-1 font-mono text-xs">{{ opportunity.starts_at }}</p>
              </div>
              <div>
                <p class="hud-label">Duration</p>
                <p class="mt-1 font-mono text-xs">{{ opportunity.duration }}</p>
              </div>
              <div>
                <p class="hud-label">Eligibility</p>
                <p :class="opportunity.eligibility.class">
                  {{ opportunity.eligibility.label }}
                </p>
              </div>
            </div>
          </div>
          <div class="flex items-center justify-between gap-4 border-t border-base-300 bg-base-200/50 px-4 py-3">
            <p class="text-xs text-base-content/50">{{ page.opportunities.footer }}</p>
            <button
              :id="page.opportunities.create_action.id"
              type="button"
              :disabled="page.opportunities.create_action.disabled"
              class="btn btn-primary btn-sm font-mono text-xs uppercase tracking-wider"
              @click="createPlan"
            >
              {{ page.opportunities.create_action.label }}
            </button>
          </div>
        </CadencePanel>
      </div>

      <aside class="min-w-0 space-y-5">
        <CadencePanel class="border border-base-300 bg-base-200/20" header-class="border-b border-base-300 px-4 py-3">
          <template #header>
            <p class="hud-label">{{ page.journey.heading }}</p>
          </template>
          <div class="space-y-3 p-4 text-sm">
            <div
              v-for="step in page.journey.steps"
              :key="step.label"
              class="flex items-center gap-3"
            >
              <span
                :class="[
                  'flex h-5 w-5 items-center justify-center border font-mono text-[0.6rem]',
                  step.complete && 'border-success/50 bg-success/10 text-success',
                  !step.complete && 'border-base-300 text-base-content/30'
                ]"
              >{{ step.complete ? "✓" : "·" }}</span>
              <span class="flex-1 text-base-content/60">{{ step.label }}</span>
              <span class="font-mono text-xs">{{ step.state }}</span>
            </div>
          </div>
        </CadencePanel>

        <CadencePanel class="border border-base-300 bg-base-200/20" header-class="border-b border-base-300 px-4 py-3">
          <template #header>
            <p class="hud-label">{{ page.versions.heading }}</p>
          </template>
          <div :id="page.versions.id">
            <div
              v-for="version in requirement_versions"
              :id="version.__dom_id"
              :key="version.contact_requirement_version_id"
              class="border-b border-base-300 px-4 py-3 last:border-b-0"
            >
              <div class="flex items-center justify-between">
                <span class="font-mono text-xs text-primary">{{ version.version_label }}</span>
                <span class="font-mono text-[0.65rem] text-base-content/45">
                  {{ version.created_at }}
                </span>
              </div>
              <p class="mt-2 text-xs text-base-content/55">{{ version.rationale }}</p>
              <p class="mt-2 truncate font-mono text-[0.6rem] text-base-content/35">
                {{ version.content_sha256 }}
              </p>
            </div>
          </div>
        </CadencePanel>
      </aside>
    </div>
  </section>
</template>
