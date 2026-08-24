<script setup lang="ts">
type Breadcrumb = {
  label: string
  href: string | null
}

type NewRule = {
  id: string
  label: string
  href: string
}

type EmptyState = {
  title: string
  description: string
}

type RoutingRuleRow = {
  id: string
  purpose_label: string
  display_name: string
  direction: string
  transport_name: string
  role: string
  state: "ENABLED" | "DISABLED"
  href: string
}

type Page = {
  title: string
  subtitle: string
  breadcrumbs: Breadcrumb[]
  new_rule: NewRule
  empty_state: EmptyState
  rules_id: string
  rows: RoutingRuleRow[]
}

defineProps<{page: Page}>()
</script>

<template>
  <div class="space-y-6">
    <header class="border-b border-primary/20 pb-4">
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

          <h1 class="mt-2 text-2xl font-bold text-base-content tracking-tight">
            {{ page.title }}
          </h1>
          <p class="mt-1 max-w-3xl text-sm text-base-content/70">
            {{ page.subtitle }}
          </p>
        </div>

        <div class="flex items-center gap-2">
          <a
            :id="page.new_rule.id"
            :href="page.new_rule.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="btn btn-primary btn-sm gap-1"
          >
            <span class="hero-plus h-4 w-4"></span> {{ page.new_rule.label }}
          </a>
        </div>
      </div>
    </header>

    <div
      v-if="page.rows.length === 0"
      class="rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
    >
      <p class="hud-label">{{ page.empty_state.title }}</p>
      <p class="mt-2 max-w-md mx-auto text-sm text-base-content/70">
        {{ page.empty_state.description }}
      </p>
    </div>

    <div v-else :id="page.rules_id" class="grid gap-3 md:grid-cols-2">
      <a
        v-for="row in page.rows"
        :id="row.id"
        :key="row.id"
        :href="row.href"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="card bg-base-200 border border-base-300 hud-corners hover:border-primary/50 hover-glow-cyan transition-glow"
      >
        <div class="card-body p-5">
          <p class="hud-label">{{ row.purpose_label }}</p>
          <h2 class="mt-2 font-semibold">{{ row.display_name }}</h2>
          <p class="mt-2 text-sm text-base-content/60">
            {{ row.direction }} via {{ row.transport_name }}
          </p>
          <p class="mt-2 font-mono text-xs text-base-content/60">
            {{ row.role }} · {{ row.state }}
          </p>
        </div>
      </a>
    </div>
  </div>
</template>
