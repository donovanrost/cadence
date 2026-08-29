<script setup lang="ts">
import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"
import {onBeforeUnmount, reactive, watch} from "vue"

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

type SearchField = {
  id: string
  name: string
  type: "search"
  label: string
  placeholder: string
  debounce_ms: number
}

type FilterValues = {
  status: string
  target: string
  query: string
}

type EmptyPayload = Record<string, never>
type FollowPayload = {"command-request-id": string}

type Command = {
  id: string
  __dom_id: string
  command_request_id: string
  command_name: string
  status: {
    value: string
    label: string
    class: string
  }
  target: {
    label: string
    display: string | null
  }
  requester: {
    label: string
    display: string
  }
  age: {
    label: string
    display: string
  }
  focus: {
    following: boolean
    label: string
    class: string
    action: {
      id: string
      label: string
      icon: string
      payload: FollowPayload
    }
  }
  evidence: {
    summary: string
    request_state: {
      label: string
      display: string
    }
    queue_entry: {
      label: string
      record_id: string | null
      display: string
    }
    release_attempt: {
      label: string
      record_id: string | null
      display: string
    }
    verification: {
      label: string
      state: string | null
      display: string
    }
  }
}

const props = defineProps<{
  page: {
    id: string
    header: {
      eyebrow: string
      heading: string
      copy: string
    }
    rows_id: string
  }
  summary: {
    id: string
    active_count: number
    observed: string
    metrics: Array<{
      label: string
      value: number
      value_class: string
    }>
  }
  filters: {
    id: string
    values: FilterValues
    fields: {
      status: SelectField
      target: SelectField
      query: SearchField
    }
  }
  reset: {
    id: string
    label: string
    payload: EmptyPayload
  }
  focus_banner: {
    id: string
    command_request_id: string
    icon: string
    prefix: string
    suffix: string
    clear: {
      id: string
      label: string
      payload: EmptyPayload
    }
  } | null
  empty: {
    id: string
    icon: string
    heading: string
    copy: string
  }
  commands: Command[]
}>()

const emit = defineEmits<{
  filter: [payload: {filters: FilterValues}]
  reset_filters: [payload: EmptyPayload]
  follow_command: [payload: FollowPayload]
  clear_command_focus: [payload: EmptyPayload]
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
  emit("filter", {filters: {...filterValues}})
}

const updateSelect = (key: "status" | "target", event: Event) => {
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

const resetFilters = () => {
  if (queryTimer !== undefined) clearTimeout(queryTimer)
  queryTimer = undefined
  emit("reset_filters", props.reset.payload)
}

const followCommand = (command: Command) => {
  emit("follow_command", command.focus.action.payload)
}

const clearCommandFocus = () => {
  if (props.focus_banner) emit("clear_command_focus", props.focus_banner.clear.payload)
}
</script>

<template>
  <section :id="page.id" class="h-full overflow-y-auto bg-base-100">
    <CadencePageHeaderFrame variant="ops">
      <div class="mx-auto flex max-w-[100rem] flex-col gap-5 xl:flex-row xl:items-end xl:justify-between">
        <div>
          <p class="font-mono text-[0.65rem] uppercase tracking-[0.28em] text-primary/70">
            {{ page.header.eyebrow }}
          </p>
          <h1 class="mt-1 text-2xl font-bold tracking-tight">{{ page.header.heading }}</h1>
          <p class="mt-2 max-w-3xl text-sm text-base-content/60">
            {{ page.header.copy }}
          </p>
        </div>
        <div
          :id="summary.id"
          class="grid grid-cols-2 gap-px border border-base-300 bg-base-300 sm:grid-cols-4"
          :data-command-active-count="summary.active_count"
        >
          <div
            v-for="metric in summary.metrics"
            :key="metric.label"
            class="min-w-24 bg-base-100/80 px-3 py-2"
          >
            <p class="hud-label">{{ metric.label }}</p>
            <p
              class="mt-1 font-mono text-lg font-semibold"
              :class="metric.value_class"
            >
              {{ metric.value }}
            </p>
          </div>
        </div>
      </div>
    </CadencePageHeaderFrame>

    <div class="mx-auto max-w-[100rem] space-y-4 p-5 lg:p-7">
      <div
        v-if="focus_banner"
        :id="focus_banner.id"
        :data-followed-command="focus_banner.command_request_id"
        class="flex items-center gap-3 border-l-2 border-info bg-info/10 px-3 py-2"
      >
        <span :class="[focus_banner.icon, 'h-4 w-4 text-info']"></span>
        <p class="min-w-0 flex-1 truncate text-sm">
          {{ focus_banner.prefix }}
          <span class="font-mono font-semibold">{{ focus_banner.command_request_id }}</span>
          {{ focus_banner.suffix }}
        </p>
        <button
          :id="focus_banner.clear.id"
          type="button"
          class="btn btn-ghost btn-xs"
          @click="clearCommandFocus"
        >
          {{ focus_banner.clear.label }}
        </button>
      </div>

      <form
        :id="filters.id"
        class="grid gap-3 border border-base-300 bg-base-200/25 p-3 md:grid-cols-3"
        @submit.prevent
      >
        <div class="fieldset mb-3">
          <label>
            <span class="hud-label block mb-1.5">{{ filters.fields.status.label }}</span>
            <select
              :id="filters.fields.status.id"
              :name="filters.fields.status.name"
              :value="filterValues.status"
              class="w-full select"
              @change="updateSelect('status', $event)"
            >
              <option
                v-for="option in filters.fields.status.options"
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
            <span class="hud-label block mb-1.5">{{ filters.fields.target.label }}</span>
            <select
              :id="filters.fields.target.id"
              :name="filters.fields.target.name"
              :value="filterValues.target"
              class="w-full select"
              @change="updateSelect('target', $event)"
            >
              <option
                v-for="option in filters.fields.target.options"
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
            <span class="hud-label block mb-1.5">{{ filters.fields.query.label }}</span>
            <input
              :id="filters.fields.query.id"
              :name="filters.fields.query.name"
              :type="filters.fields.query.type"
              :value="filterValues.query"
              :placeholder="filters.fields.query.placeholder"
              class="w-full input"
              @input="updateQuery"
            >
          </label>
        </div>
      </form>

      <div class="flex items-center justify-between gap-3">
        <p class="font-mono text-[0.65rem] uppercase tracking-wider text-base-content/45">
          {{ summary.observed }}
        </p>
        <button
          :id="reset.id"
          type="button"
          class="btn btn-ghost btn-xs"
          @click="resetFilters"
        >
          {{ reset.label }}
        </button>
      </div>

      <section class="overflow-hidden border border-base-300 bg-base-100">
        <div :id="page.rows_id">
          <div
            :id="empty.id"
            class="hidden only:flex min-h-48 flex-col items-center justify-center px-6 text-center"
          >
            <span :class="[empty.icon, 'h-8 w-8 text-base-content/30']"></span>
            <p class="mt-3 font-semibold">{{ empty.heading }}</p>
            <p class="mt-1 text-sm text-base-content/55">
              {{ empty.copy }}
            </p>
          </div>
          <article
            v-for="command in commands"
            :id="command.__dom_id"
            :key="command.id"
            :data-command-request="command.command_request_id"
            :data-command-state="command.status.value"
            class="grid gap-3 border-b border-base-300/60 px-4 py-3 last:border-b-0 xl:grid-cols-[9rem_minmax(0,1fr)_13rem_10rem_10rem_auto] xl:items-center"
          >
            <span :class="command.status.class">{{ command.status.label }}</span>
            <div class="min-w-0">
              <p class="truncate font-semibold">{{ command.command_name }}</p>
              <p class="truncate font-mono text-[0.68rem] text-base-content/50">
                {{ command.command_request_id }}
              </p>
            </div>
            <div>
              <p class="hud-label">{{ command.target.label }}</p>
              <p class="mt-1 truncate font-mono text-[0.68rem]">{{ command.target.display }}</p>
            </div>
            <div>
              <p class="hud-label">{{ command.requester.label }}</p>
              <p class="mt-1 truncate text-xs">{{ command.requester.display }}</p>
            </div>
            <div>
              <p class="hud-label">{{ command.age.label }}</p>
              <p class="mt-1 font-mono text-[0.68rem]">{{ command.age.display }}</p>
            </div>
            <div class="flex justify-end">
              <button
                v-if="!command.focus.following"
                :id="command.focus.action.id"
                type="button"
                class="btn btn-ghost btn-xs"
                @click="followCommand(command)"
              >
                <span :class="[command.focus.action.icon, 'h-3.5 w-3.5']"></span>
                {{ command.focus.action.label }}
              </button>
              <span v-else :class="command.focus.class">
                {{ command.focus.label }}
              </span>
            </div>
            <CadenceDetailsFrame class="xl:col-span-6 border-t border-base-300/50 pt-2">
              <summary class="cursor-pointer font-mono text-[0.65rem] uppercase tracking-wider text-base-content/50">
                {{ command.evidence.summary }}
              </summary>
              <dl class="mt-2 grid gap-2 text-xs sm:grid-cols-2 lg:grid-cols-4">
                <div>
                  <dt class="hud-label">{{ command.evidence.request_state.label }}</dt>
                  <dd class="mt-1 break-all font-mono text-[0.68rem]">
                    {{ command.evidence.request_state.display }}
                  </dd>
                </div>
                <div>
                  <dt class="hud-label">{{ command.evidence.queue_entry.label }}</dt>
                  <dd class="mt-1 break-all font-mono text-[0.68rem]">
                    {{ command.evidence.queue_entry.display }}
                  </dd>
                </div>
                <div>
                  <dt class="hud-label">{{ command.evidence.release_attempt.label }}</dt>
                  <dd class="mt-1 break-all font-mono text-[0.68rem]">
                    {{ command.evidence.release_attempt.display }}
                  </dd>
                </div>
                <div>
                  <dt class="hud-label">{{ command.evidence.verification.label }}</dt>
                  <dd class="mt-1 break-all font-mono text-[0.68rem]">
                    {{ command.evidence.verification.display }}
                  </dd>
                </div>
              </dl>
            </CadenceDetailsFrame>
          </article>
        </div>
      </section>
    </div>
  </section>
</template>
