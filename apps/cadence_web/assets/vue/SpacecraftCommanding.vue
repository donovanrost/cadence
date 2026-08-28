<script setup lang="ts">
import StatusBadge from "./StatusBadge.vue"
import CadenceCard from "./ui/components/CadenceCard.vue"
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"

type Status = {
  tone: "info"
  label: string
}

type Breadcrumb = {
  label: string
  href: string | null
}

type CommandingPage = {
  id: string
  title: string
  subtitle: string
  eyebrow: string
  breadcrumbs: Breadcrumb[]
  status: Status
}

type CommandPanel = {
  id: string
  title: string
  value: string
  status: Status
  description: string
}

type ReadinessImpact = {
  eyebrow: string
  title: string
  description: string
  status: Status
}

defineProps<{
  page: CommandingPage
  panels: CommandPanel[]
  readiness: ReadinessImpact
}>()
</script>

<template>
  <div :id="page.id" class="space-y-6">
    <CadencePageHeaderFrame variant="compact">
      <div class="flex items-end justify-between gap-4">
        <div>
          <nav
            aria-label="Breadcrumb"
            class="flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
          >
            <template
              v-for="(breadcrumb, index) in page.breadcrumbs"
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
          </nav>
          <p class="hud-label">{{ page.eyebrow }}</p>
          <h1 class="mt-2 text-2xl font-bold text-base-content tracking-tight">
            {{ page.title }}
          </h1>
          <p class="mt-1 max-w-3xl text-sm text-base-content/70">{{ page.subtitle }}</p>
        </div>
        <div class="flex items-center gap-2">
          <StatusBadge :status="page.status.tone" :label="page.status.label" />
        </div>
      </div>
    </CadencePageHeaderFrame>

    <section class="grid gap-4 lg:grid-cols-3">
      <CadenceCard
        v-for="panel in panels"
        :id="panel.id"
        :key="panel.id"
        class="card bg-base-200 border border-base-300"
        body-class="card-body p-6"
      >
          <div class="flex items-start justify-between gap-3">
            <div>
              <p class="hud-label mb-2">{{ panel.title }}</p>
              <h2 class="text-base font-semibold">{{ panel.value }}</h2>
            </div>
            <StatusBadge :status="panel.status.tone" :label="panel.status.label" />
          </div>
          <p class="mt-3 text-sm text-base-content/70">{{ panel.description }}</p>
      </CadenceCard>
    </section>

    <CadenceCard class="card bg-base-200 border border-base-300" body-class="card-body p-6">
        <div class="flex items-start justify-between gap-4">
          <div>
            <p class="hud-label mb-2">{{ readiness.eyebrow }}</p>
            <h2 class="text-lg font-semibold">{{ readiness.title }}</h2>
            <p class="mt-1 max-w-2xl text-sm text-base-content/70">
              {{ readiness.description }}
            </p>
          </div>
          <div class="flex flex-wrap items-center justify-end gap-2">
            <StatusBadge :status="readiness.status.tone" :label="readiness.status.label" />
          </div>
        </div>
    </CadenceCard>
  </div>
</template>
