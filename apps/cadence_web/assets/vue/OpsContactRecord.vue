<script setup lang="ts">
import CadencePanel from "./ui/components/CadencePanel.vue"

type Action = {
  id: string
  label: string
  icon: string
  class: string
  href: string
}

type Fact = {
  label: string
  value: string
}

type LineageField = Fact & {
  class: string
}

type ContactPath = {
  id: string
  path_id: string
  source_endpoint_ref: string
  direction: Fact
  selection: Fact
}

type ContactRecord = {
  id: string
  header: {
    title: string
    canonical_id: string
    lifecycle: {
      label: string
      class: string
    }
    back: {
      id: string
      label: string
      icon: string
      href: string
    }
    actions: Action[]
  }
  window: {
    id: string
    eyebrow: string
    title: string
    facts: Fact[]
  }
  paths: {
    id: string
    list_id: string
    eyebrow: string
    title: string
    empty: boolean
    empty_state: {
      id: string
      message: string
    }
    rows: ContactPath[]
  }
  lineage: {
    id: string
    eyebrow: string
    title: string
    fields: LineageField[]
  }
  context: {
    id: string
    eyebrow: string
    title: string
    intents: {
      label: string
      empty: boolean
      empty_state: string
      values: string[]
    }
    sources: {
      label: string
      empty: boolean
      empty_state: string
      values: string[]
    }
  }
}

defineProps<{
  record: ContactRecord
}>()
</script>

<template>
  <main :id="record.id" class="min-h-0 flex-1 overflow-y-auto bg-base-100">
    <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">
      <div class="mx-auto flex max-w-[90rem] flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div class="min-w-0">
          <a
            :id="record.header.back.id"
            :href="record.header.back.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="inline-flex items-center gap-1 font-mono text-[0.65rem] uppercase tracking-[0.18em] text-primary/70 hover:text-primary"
          >
            <span :class="[record.header.back.icon, 'h-3 w-3']"></span>
            {{ record.header.back.label }}
          </a>
          <div class="mt-3 flex flex-wrap items-center gap-3">
            <h1 class="text-2xl font-bold tracking-tight">{{ record.header.title }}</h1>
            <span
              :class="[
                'border px-2 py-1 font-mono text-[0.65rem] font-bold uppercase tracking-[0.14em]',
                record.header.lifecycle.class
              ]"
            >
              {{ record.header.lifecycle.label }}
            </span>
          </div>
          <p
            id="contact-record-id"
            class="mt-2 break-all font-mono text-xs text-base-content/50"
          >
            {{ record.header.canonical_id }}
          </p>
        </div>

        <div class="flex flex-wrap gap-2">
          <a
            v-for="action in record.header.actions"
            :id="action.id"
            :key="action.id"
            :href="action.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            :class="action.class"
          >
            <span :class="[action.icon, 'h-4 w-4']"></span>
            {{ action.label }}
          </a>
        </div>
      </div>
    </header>

    <div class="mx-auto grid max-w-[90rem] gap-5 p-5 xl:grid-cols-[minmax(0,1.35fr)_minmax(22rem,0.65fr)] lg:p-7">
      <div class="min-w-0 space-y-5">
        <CadencePanel :id="record.window.id" class="border border-base-300 bg-base-200/25" header-class="border-b border-base-300 px-4 py-3">
          <template #header>
            <p class="hud-label">{{ record.window.eyebrow }}</p>
            <h2 class="mt-1 text-base font-semibold">{{ record.window.title }}</h2>
          </template>
          <div class="grid gap-px bg-base-300 sm:grid-cols-2 xl:grid-cols-4">
            <div
              v-for="fact in record.window.facts"
              :key="fact.label"
              class="bg-base-100 px-4 py-4"
            >
              <p class="hud-label">{{ fact.label }}</p>
              <p class="mt-2 font-mono text-xs text-base-content/75">{{ fact.value }}</p>
            </div>
          </div>
        </CadencePanel>

        <CadencePanel :id="record.paths.id" class="border border-base-300 bg-base-200/20" header-class="border-b border-base-300 px-4 py-3">
          <template #header>
            <p class="hud-label">{{ record.paths.eyebrow }}</p>
            <h2 class="mt-1 text-base font-semibold">{{ record.paths.title }}</h2>
          </template>
          <div :id="record.paths.list_id" class="divide-y divide-base-300">
            <div
              v-if="record.paths.empty"
              :id="record.paths.empty_state.id"
              class="px-4 py-8 text-sm text-base-content/50"
            >
              {{ record.paths.empty_state.message }}
            </div>
            <template v-else>
              <article
                v-for="path in record.paths.rows"
                :id="path.id"
                :key="path.id"
                class="grid gap-3 px-4 py-4 md:grid-cols-[minmax(12rem,1fr)_9rem_9rem]"
              >
                <div class="min-w-0">
                  <p class="font-mono text-xs font-semibold">{{ path.path_id }}</p>
                  <p class="mt-1 truncate font-mono text-[0.68rem] text-base-content/45">
                    {{ path.source_endpoint_ref }}
                  </p>
                </div>
                <div>
                  <p class="hud-label">{{ path.direction.label }}</p>
                  <p class="mt-1 font-mono text-xs text-base-content/70">
                    {{ path.direction.value }}
                  </p>
                </div>
                <div>
                  <p class="hud-label">{{ path.selection.label }}</p>
                  <p class="mt-1 font-mono text-xs text-base-content/70">
                    {{ path.selection.value }}
                  </p>
                </div>
              </article>
            </template>
          </div>
        </CadencePanel>
      </div>

      <aside class="min-w-0 space-y-5">
        <CadencePanel :id="record.lineage.id" class="border border-base-300 bg-base-200/25" header-class="border-b border-base-300 px-4 py-3">
          <template #header>
            <p class="hud-label">{{ record.lineage.eyebrow }}</p>
            <h2 class="mt-1 text-base font-semibold">{{ record.lineage.title }}</h2>
          </template>
          <dl class="grid grid-cols-[8rem_minmax(0,1fr)] gap-x-3 gap-y-3 p-4 text-xs">
            <template v-for="field in record.lineage.fields" :key="field.label">
              <dt class="text-base-content/45">{{ field.label }}</dt>
              <dd :class="field.class">{{ field.value }}</dd>
            </template>
          </dl>
        </CadencePanel>

        <CadencePanel :id="record.context.id" class="border border-base-300 bg-base-200/20" header-class="border-b border-base-300 px-4 py-3">
          <template #header>
            <p class="hud-label">{{ record.context.eyebrow }}</p>
            <h2 class="mt-1 text-base font-semibold">{{ record.context.title }}</h2>
          </template>
          <div class="space-y-4 p-4 text-xs">
            <div>
              <p class="hud-label">{{ record.context.intents.label }}</p>
              <div class="mt-2 flex flex-wrap gap-1.5">
                <span
                  v-for="intent in record.context.intents.values"
                  :key="intent"
                  class="border border-primary/25 bg-primary/5 px-2 py-1 font-mono text-[0.65rem]"
                >
                  {{ intent }}
                </span>
                <span v-if="record.context.intents.empty" class="text-base-content/45">
                  {{ record.context.intents.empty_state }}
                </span>
              </div>
            </div>
            <div>
              <p class="hud-label">{{ record.context.sources.label }}</p>
              <ul class="mt-2 space-y-1.5 font-mono text-[0.68rem] text-base-content/65">
                <li v-for="source in record.context.sources.values" :key="source">{{ source }}</li>
                <li
                  v-if="record.context.sources.empty"
                  class="font-sans text-base-content/45"
                >
                  {{ record.context.sources.empty_state }}
                </li>
              </ul>
            </div>
          </div>
        </CadencePanel>
      </aside>
    </div>
  </main>
</template>
