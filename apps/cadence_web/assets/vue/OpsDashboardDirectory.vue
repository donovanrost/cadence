<script setup lang="ts">
import CadenceToggle from "./ui/reka/CadenceToggle.vue"
import {onBeforeUnmount, reactive, watch} from "vue"

type LinkAction = {
  id: string
  label: string
  icon: string
  href: string
}

type HeaderAction = LinkAction & {
  icon_class: string
  class: string
}

type Page = {
  id: string
  header: {
    eyebrow: string
    heading: string
    copy: string
    count: {
      id: string
      value: number
      suffix: string
    }
    author_actions: HeaderAction[]
  }
  list: {
    id: string
    empty: {
      id: string
      icon: string
      heading: string
      copy: string
    }
  }
}

type Option = {
  label: string
  value: string
}

type SelectField = {
  id: string
  name: string
  type: "select"
  label: string
  options: Option[]
}

type FilterValues = {
  query: string
  lifecycle: string
  tag: string
  sort: string
}

type Filters = {
  id: string
  values: FilterValues
  fields: {
    query: {
      id: string
      name: string
      type: "search"
      label: string
      placeholder: string
      debounce_ms: number
    }
    lifecycle: SelectField
    tag: SelectField
    sort: SelectField
  }
}

type StarPayload = {
  "dashboard-id": string
  starred: string
}

type RestorePayload = {
  "dashboard-id": string
  "expected-version": string
}

type DirectoryRow = {
  id: string
  __dom_id: string
  dashboard_id: string
  name: string
  description: string | null
  tags: string[]
  lifecycle: {
    state: "active" | "archived"
    class: string
  }
  starred: boolean
  open: {
    id: string
    href: string
  } | null
  star: {
    id: string
    payload: StarPayload
    aria_label: string
    aria_pressed: string
    disabled: boolean
    title: string | null
    icon: string
  }
  widget_version_label: string
  clone?: LinkAction
  restore: {
    id: string
    label: string
    icon: string
    payload: RestorePayload
    disabled: boolean
    lifecycle_action: string
    action_available: string
  } | null
}

const props = defineProps<{
  page: Page
  filters: Filters
  dashboard_directory: DirectoryRow[]
}>()

const emit = defineEmits<{
  filter_dashboards: [payload: {directory: FilterValues}]
  toggle_dashboard_star: [payload: StarPayload]
  restore_dashboard: [payload: RestorePayload]
}>()

const filterValues = reactive<FilterValues>({...props.filters.values})
let queryTimer: ReturnType<typeof setTimeout> | undefined

watch(
  () => props.filters.values,
  values => {
    if (queryTimer !== undefined) clearTimeout(queryTimer)
    queryTimer = undefined
    Object.assign(filterValues, values)
  },
  {deep: true}
)

onBeforeUnmount(() => {
  if (queryTimer !== undefined) clearTimeout(queryTimer)
})

const emitFilters = () => {
  emit("filter_dashboards", {directory: {...filterValues}})
}

const updateSelect = (key: "lifecycle" | "tag" | "sort", event: Event) => {
  if (queryTimer !== undefined) clearTimeout(queryTimer)
  queryTimer = undefined
  filterValues[key] = (event.target as HTMLSelectElement).value
  emitFilters()
}

const updateQuery = (event: Event) => {
  filterValues.query = (event.target as HTMLInputElement).value

  if (queryTimer !== undefined) clearTimeout(queryTimer)
  queryTimer = setTimeout(() => {
    queryTimer = undefined
    emitFilters()
  }, props.filters.fields.query.debounce_ms)
}

const toggleDashboardStar = (row: DirectoryRow) => {
  emit("toggle_dashboard_star", row.star.payload)
}

const restoreDashboard = (row: DirectoryRow) => {
  if (row.restore) emit("restore_dashboard", row.restore.payload)
}
</script>

<template>
  <section :id="page.id" class="h-full overflow-y-auto bg-base-100">
    <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">
      <div class="mx-auto flex max-w-[100rem] flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <p class="font-mono text-[0.65rem] uppercase tracking-[0.2em] text-primary/70">
            {{ page.header.eyebrow }}
          </p>
          <h1 class="mt-1 text-2xl font-bold tracking-tight">{{ page.header.heading }}</h1>
          <p class="mt-2 max-w-3xl text-sm text-base-content/60">
            {{ page.header.copy }}
          </p>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <span
            :id="page.header.count.id"
            class="font-mono text-xs uppercase tracking-wider text-base-content/50"
          >
            {{ page.header.count.value }} {{ page.header.count.suffix }}
          </span>
          <a
            v-for="action in page.header.author_actions"
            :id="action.id"
            :key="action.id"
            :href="action.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            :class="action.class"
          >
            <span :class="[action.icon, action.icon_class]" aria-hidden="true"></span>
            {{ action.label }}
          </a>
        </div>
      </div>
    </header>

    <div class="mx-auto max-w-[100rem] space-y-5 p-5 lg:p-7">
      <form
        :id="filters.id"
        class="grid gap-3 border border-base-300 bg-base-200/25 p-3 md:grid-cols-4"
        @submit.prevent
      >
        <div class="fieldset mb-3">
          <label>
            <span class="hud-label block mb-1.5">{{ filters.fields.query.label }}</span>
            <input
              :id="filters.fields.query.id"
              :name="filters.fields.query.name"
              :type="filters.fields.query.type"
              :value="filterValues.query"
              :placeholder="filters.fields.query.placeholder"
              class="w-full input"
              phx-debounce="250"
              @input="updateQuery"
            >
          </label>
        </div>
        <div class="fieldset mb-3">
          <label>
            <span class="hud-label block mb-1.5">{{ filters.fields.lifecycle.label }}</span>
            <select
              :id="filters.fields.lifecycle.id"
              :name="filters.fields.lifecycle.name"
              :value="filterValues.lifecycle"
              class="w-full select"
              @change="updateSelect('lifecycle', $event)"
            >
              <option
                v-for="option in filters.fields.lifecycle.options"
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
            <span class="hud-label block mb-1.5">{{ filters.fields.tag.label }}</span>
            <select
              :id="filters.fields.tag.id"
              :name="filters.fields.tag.name"
              :value="filterValues.tag"
              class="w-full select"
              @change="updateSelect('tag', $event)"
            >
              <option
                v-for="option in filters.fields.tag.options"
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
            <span class="hud-label block mb-1.5">{{ filters.fields.sort.label }}</span>
            <select
              :id="filters.fields.sort.id"
              :name="filters.fields.sort.name"
              :value="filterValues.sort"
              class="w-full select"
              @change="updateSelect('sort', $event)"
            >
              <option
                v-for="option in filters.fields.sort.options"
                :key="option.value"
                :value="option.value"
              >
                {{ option.label }}
              </option>
            </select>
          </label>
        </div>
      </form>

      <div :id="page.list.id" class="grid gap-3 xl:grid-cols-2">
        <div
          :id="page.list.empty.id"
          class="hidden only:flex min-h-56 flex-col items-center justify-center border border-dashed border-base-300 px-6 text-center xl:col-span-2"
        >
          <span
            :class="[page.list.empty.icon, 'h-8 w-8 text-base-content/30']"
            aria-hidden="true"
          ></span>
          <p class="mt-3 font-semibold">{{ page.list.empty.heading }}</p>
          <p class="mt-1 text-sm text-base-content/55">
            {{ page.list.empty.copy }}
          </p>
        </div>

        <article
          v-for="row in dashboard_directory"
          :id="row.__dom_id"
          :key="row.id"
          :data-dashboard-directory-id="row.dashboard_id"
          :data-dashboard-directory-lifecycle="row.lifecycle.state"
          :data-dashboard-directory-starred="row.star.aria_pressed"
          class="group border border-base-300 bg-base-100 p-4 transition-colors hover:border-primary/45"
        >
          <div class="flex items-start gap-3">
            <div class="min-w-0 flex-1">
              <div class="flex flex-wrap items-center gap-2">
                <a
                  v-if="row.open"
                  :id="row.open.id"
                  :href="row.open.href"
                  data-phx-link="redirect"
                  data-phx-link-state="push"
                  class="truncate text-sm font-semibold text-primary hover:underline"
                >
                  {{ row.name }}
                </a>
                <span v-else class="truncate text-sm font-semibold text-base-content/70">
                  {{ row.name }}
                </span>
                <span :class="row.lifecycle.class">{{ row.lifecycle.state }}</span>
              </div>
              <p
                v-if="row.description"
                class="mt-1 line-clamp-2 text-sm text-base-content/60"
              >
                {{ row.description }}
              </p>
              <div class="mt-3 flex flex-wrap items-center gap-1.5">
                <span
                  v-for="tag in row.tags"
                  :key="tag"
                  :data-dashboard-directory-tag="tag"
                  class="border border-primary/20 bg-primary/5 px-1.5 py-0.5 font-mono text-[0.625rem] text-primary/80"
                >
                  {{ tag }}
                </span>
                <span
                  v-if="row.tags.length === 0"
                  class="font-mono text-[0.625rem] text-base-content/35"
                >
                  untagged
                </span>
              </div>
            </div>

            <CadenceToggle
              :pressed="row.star.aria_pressed === 'true'"
              :disabled="row.star.disabled"
              @request-change="toggleDashboardStar(row)"
            >
              <button
                :id="row.star.id"
                type="button"
                :aria-label="row.star.aria_label"
                :aria-pressed="row.star.aria_pressed"
                :disabled="row.star.disabled"
                :title="row.star.title"
                :class="['btn btn-ghost btn-xs shrink-0', row.starred && 'text-warning']"
              >
                <span :class="[row.star.icon, 'h-4 w-4']" aria-hidden="true"></span>
              </button>
            </CadenceToggle>
          </div>

          <div class="mt-4 flex items-center justify-between gap-3 border-t border-base-300/60 pt-3">
            <p class="font-mono text-[0.65rem] uppercase tracking-wider text-base-content/45">
              {{ row.widget_version_label }}
            </p>
            <a
              v-if="row.clone"
              :id="row.clone.id"
              :href="row.clone.href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="btn btn-ghost btn-xs"
            >
              <span :class="[row.clone.icon, 'h-3.5 w-3.5']" aria-hidden="true"></span>
              {{ row.clone.label }}
            </a>
            <button
              v-if="row.restore"
              :id="row.restore.id"
              type="button"
              class="btn btn-ghost btn-xs"
              :disabled="row.restore.disabled"
              :data-dashboard-lifecycle-action="row.restore.lifecycle_action"
              :data-dashboard-action-available="row.restore.action_available"
              @click="restoreDashboard(row)"
            >
              <span :class="[row.restore.icon, 'h-3.5 w-3.5']" aria-hidden="true"></span>
              {{ row.restore.label }}
            </button>
          </div>
        </article>
      </div>
    </div>
  </section>
</template>
