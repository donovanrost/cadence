<script setup lang="ts">
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"
type JourneyStep = {
  number: string
  label: string
  detail: string
  active: boolean
}

type Page = {
  id: string
  header: {
    eyebrow: string
    title: string
    description: string
    create_action: {
      id: string
      label: string
      href: string
    }
  }
  journey_steps: JourneyStep[]
  empty_state: {
    id: string
    title: string
    description: string
  }
  list_id: string
}

type PriorityTone = "error" | "warning" | "neutral"

type ContactRequirementRow = {
  id: string
  __dom_id: string
  priority: {
    label: string
    tone: PriorityTone
    class: string
  }
  version_direction: string
  intent_label: string
  outcome_detail: string
  window: {
    label: string
    detail: string
  }
  journey: {
    label: string
    detail: string
  }
  detail_href: string
}

defineProps<{
  page: Page
  requirements: ContactRequirementRow[]
}>()
</script>

<template>
  <section :id="page.id" class="h-full overflow-y-auto bg-base-100">
    <CadencePageHeaderFrame variant="ops">
      <div class="mx-auto flex max-w-[96rem] flex-col gap-5 md:flex-row md:items-end md:justify-between">
        <div>
          <p class="font-mono text-[0.65rem] uppercase tracking-[0.28em] text-primary/70">
            {{ page.header.eyebrow }}
          </p>
          <h1 class="mt-1 text-2xl font-bold tracking-tight">{{ page.header.title }}</h1>
          <p class="mt-2 max-w-3xl text-sm text-base-content/60">
            {{ page.header.description }}
          </p>
        </div>
        <a
          :id="page.header.create_action.id"
          :href="page.header.create_action.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="btn btn-primary btn-sm gap-2 font-mono text-xs uppercase tracking-wider"
        >
          <span class="hero-plus h-4 w-4" aria-hidden="true"></span>
          {{ page.header.create_action.label }}
        </a>
      </div>
    </CadencePageHeaderFrame>

    <div class="mx-auto max-w-[96rem] p-5 lg:p-7">
      <div class="mb-5 grid border border-base-300 bg-base-200/25 sm:grid-cols-4">
        <div
          v-for="step in page.journey_steps"
          :key="step.number"
          :class="[
            'border-b border-base-300 px-4 py-3 sm:border-b-0 sm:border-r last:border-r-0',
            step.active && 'bg-primary/[0.06]'
          ]"
        >
          <p class="font-mono text-[0.6rem] tracking-[0.2em] text-primary/60">
            {{ step.number }}
          </p>
          <p class="mt-1 text-sm font-semibold">{{ step.label }}</p>
          <p class="mt-0.5 text-xs text-base-content/45">{{ step.detail }}</p>
        </div>
      </div>

      <div
        v-if="requirements.length === 0"
        :id="page.empty_state.id"
        class="border border-dashed border-base-300 bg-base-200/20 px-6 py-16 text-center"
      >
        <span
          class="hero-clipboard-document-list mx-auto h-8 w-8 text-primary/40"
          aria-hidden="true"
        ></span>
        <h2 class="mt-4 text-lg font-semibold">{{ page.empty_state.title }}</h2>
        <p class="mx-auto mt-2 max-w-xl text-sm text-base-content/60">
          {{ page.empty_state.description }}
        </p>
      </div>

      <div :id="page.list_id" class="space-y-3">
        <a
          v-for="row in requirements"
          :id="row.__dom_id"
          :key="row.id"
          :href="row.detail_href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="group block border border-base-300 bg-base-200/20 transition-colors hover:border-primary/50 hover:bg-primary/[0.03]"
        >
          <div class="grid gap-4 px-4 py-4 md:grid-cols-[minmax(0,1.4fr)_minmax(15rem,0.8fr)_auto] md:items-center">
            <div class="min-w-0">
              <div class="flex flex-wrap items-center gap-2">
                <span :class="row.priority.class" :data-tone="row.priority.tone">
                  {{ row.priority.label }}
                </span>
                <span class="font-mono text-[0.65rem] uppercase tracking-wider text-base-content/45">
                  {{ row.version_direction }}
                </span>
              </div>
              <h2 class="mt-2 truncate text-base font-semibold group-hover:text-primary">
                {{ row.intent_label }}
              </h2>
              <p class="mt-1 truncate text-sm text-base-content/55">
                {{ row.outcome_detail }}
              </p>
            </div>
            <div>
              <p class="hud-label">{{ row.window.label }}</p>
              <p class="mt-1 font-mono text-xs tabular-nums text-base-content/75">
                {{ row.window.detail }}
              </p>
              <div class="mt-2 h-1.5 overflow-hidden bg-base-300">
                <div class="h-full w-2/3 bg-primary/65"></div>
              </div>
            </div>
            <div class="min-w-36 border-l border-base-300 pl-4">
              <p class="hud-label">Journey state</p>
              <p class="mt-1 text-sm font-semibold text-base-content/80">
                {{ row.journey.label }}
              </p>
              <p class="mt-1 font-mono text-[0.65rem] text-base-content/45">
                {{ row.journey.detail }}
              </p>
            </div>
          </div>
        </a>
      </div>
    </div>
  </section>
</template>
