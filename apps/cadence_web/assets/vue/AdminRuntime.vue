<script setup lang="ts">
import {reactive, watch} from "vue"
import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"
import CadenceCompactPageHeaderBodyFrame from "./ui/components/CadenceCompactPageHeaderBodyFrame.vue"
import CadenceDataRow from "./ui/components/CadenceDataRow.vue"
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"
import CadencePageTitle from "./ui/components/CadencePageTitle.vue"
import CadencePanel from "./ui/components/CadencePanel.vue"
import CadenceStatTile from "./ui/components/CadenceStatTile.vue"
import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"

type FilterKey =
  | "dashboard_id"
  | "mission_id"
  | "boundary"
  | "context_reason"
  | "replay_run_id"
  | "affected_placement_id"

type FilterValues = Record<FilterKey, string>

type FilterField = {
  key: FilterKey
  id: string
  name: string
  label: string
  placeholder: string
}

type Summary = {
  decision_count: number
  status_summary: string
  refresh_summary: string
  source_summary: string
  selected_decision_state: "none" | "missing" | "visible" | "outside_results"
  empty_state: {
    id: string
    copy: string
  }
  stats: Array<{
    id: string
    label: string
    value: number
  }>
}

type DecisionRow = {
  __dom_id: string
  id: string
  key: string
  dashboard: string
  mission: string
  source: string
  boundary: string
  status: string
  context: string
  replay_run: string
  refresh: string
  artifacts: string
  affected_count: string
  affected_placements: string
  affected_impact: string
  observed: string
  inspect_action: {
    id: string
    href: string
    selected: boolean
  }
}

type DetailFact = {
  key: string
  label: string
  value: string
}

type DetailPair = {
  key: string
  label: string
  value: string
}

type DecisionDetail = {
  id: string
  subtitle: string
  close_action: {
    id: string
    href: string
  }
  evidence: {
    id: string
    decision_key: string
    source: string
    groups: Array<{
      key: string
      label: string
      facts: DetailFact[]
    }>
  }
  sections: Array<{
    id: string
    key: string
    label: string
    empty_copy: string
    pairs: DetailPair[]
  }>
}

const props = defineProps<{
  summary: Summary
  filters: {
    values: FilterValues
    fields: FilterField[]
    clear_href: string
  }
  decisions: DecisionRow[]
  selection: {
    state: "none" | "missing" | "visible" | "outside_results"
    decision_key: string | null
    missing: boolean
    outside_results: boolean
    context_href: string | null
    detail: DecisionDetail | null
  }
  navigation: {
    admin_href: string
  }
}>()

const emit = defineEmits<{
  refresh: []
  filter_decisions: [payload: {runtime_decision_filters: FilterValues}]
}>()

const filterKeys: FilterKey[] = [
  "dashboard_id",
  "mission_id",
  "boundary",
  "context_reason",
  "replay_run_id",
  "affected_placement_id"
]

const normalizeFilters = (values: Partial<Record<FilterKey, unknown>>): FilterValues => ({
  dashboard_id: String(values.dashboard_id ?? ""),
  mission_id: String(values.mission_id ?? ""),
  boundary: String(values.boundary ?? ""),
  context_reason: String(values.context_reason ?? ""),
  replay_run_id: String(values.replay_run_id ?? ""),
  affected_placement_id: String(values.affected_placement_id ?? "")
})

const filterValues = reactive<FilterValues>(normalizeFilters(props.filters.values))
const pendingFilterPatches: FilterValues[] = []
const sameFilters = (left: FilterValues, right: FilterValues) =>
  filterKeys.every(key => left[key] === right[key])

watch(
  () => props.filters.values,
  serverValues => {
    const normalizedServerValues = normalizeFilters(serverValues)
    const acknowledgedIndex = pendingFilterPatches.findIndex(sent =>
      sameFilters(sent, normalizedServerValues)
    )
    const hasNewerTyping =
      acknowledgedIndex >= 0 && acknowledgedIndex < pendingFilterPatches.length - 1

    if (acknowledgedIndex >= 0) pendingFilterPatches.splice(0, acknowledgedIndex + 1)
    if (!hasNewerTyping) Object.assign(filterValues, normalizedServerValues)
  },
  {deep: true}
)

const emitFilters = () => {
  const normalized = normalizeFilters(filterValues)
  pendingFilterPatches.push({...normalized})
  emit("filter_decisions", {runtime_decision_filters: normalized})
}

const updateFilter = (key: FilterKey, event: Event) => {
  const input = event.target as HTMLInputElement
  filterValues[key] = String(input.value ?? "")
  emitFilters()
}
</script>

<template>
  <div
    id="admin-runtime-page"
    class="space-y-6"
    :data-runtime-decision-count="summary.decision_count"
    :data-runtime-decision-status-summary="summary.status_summary"
    :data-runtime-decision-refresh-summary="summary.refresh_summary"
    :data-runtime-decision-source-summary="summary.source_summary"
    :data-runtime-decision-filter-dashboard="filters.values.dashboard_id"
    :data-runtime-decision-filter-mission="filters.values.mission_id"
    :data-runtime-decision-filter-boundary="filters.values.boundary"
    :data-runtime-decision-filter-context-reason="filters.values.context_reason"
    :data-runtime-decision-filter-replay-run="filters.values.replay_run_id"
    :data-runtime-decision-filter-affected-placement="filters.values.affected_placement_id"
    :data-runtime-selected-decision-state="summary.selected_decision_state"
  >
    <CadencePageHeaderFrame variant="compact">
      <CadenceCompactPageHeaderBodyFrame>
        <template #content>
          <CadenceBreadcrumbs>
            <a
              :href="navigation.admin_href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="hover:text-primary transition-colors"
            >Platform Admin</a>
            <span class="text-base-content/20" aria-hidden="true">/</span>
            <span class="text-primary/90">Runtime Diagnostics</span>
          </CadenceBreadcrumbs>
          <CadencePageTitle>
            Runtime Diagnostics
            <span class="ml-3 font-mono text-base text-base-content/60">
              {{ summary.decision_count }} decisions
            </span>
          </CadencePageTitle>
          <p class="mt-1 max-w-3xl text-sm text-base-content/70">
            Process-local runtime health for support workflows, including dashboard invalidation decisions emitted by open dashboards.
          </p>
        </template>
        <template #actions>
          <button
            id="admin-runtime-refresh"
            type="button"
            class="btn btn-secondary btn-sm"
            @click="emit('refresh')"
          >
            <span class="hero-arrow-path h-4 w-4" aria-hidden="true"></span> Refresh
          </button>
        </template>
      </CadenceCompactPageHeaderBodyFrame>
    </CadencePageHeaderFrame>

    <div class="grid gap-3 md:grid-cols-4">
      <CadenceStatTile
        v-for="stat in summary.stats"
        :id="stat.id"
        :key="stat.id"
      >
        <template #label>{{ stat.label }}</template>
        <p class="mt-1 font-mono text-xl text-base-content">{{ stat.value }}</p>
      </CadenceStatTile>
    </div>

    <CadencePanel
      class="card bg-base-200 border border-base-300"
      header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
    >
      <template #header>
        <div>
          <h2 class="text-base font-semibold text-base-content">Decision Filters</h2>
          <p class="mt-1 text-xs text-base-content/70">
            Filter durable decision history and runtime-health fallback rows by dashboard, mission, invalidation boundary, context reason, or impacted placement.
          </p>
        </div>
      </template>
      <div class="card-body p-6">
        <form
          id="admin-runtime-filter-form"
          class="grid gap-3 md:grid-cols-2 xl:grid-cols-6"
          @submit.prevent="emitFilters"
        >
          <div v-for="field in filters.fields" :key="field.key" class="fieldset">
            <label :for="field.id">
              <span class="hud-label block mb-1.5">{{ field.label }}</span>
            </label>
            <input
              :id="field.id"
              :name="field.name"
              type="text"
              :value="filterValues[field.key]"
              :placeholder="field.placeholder"
              class="w-full input"
              @input="updateFilter(field.key, $event)"
            />
          </div>
          <div class="flex items-end gap-2 md:col-span-2 xl:col-span-6">
            <button
              id="admin-runtime-apply-filters"
              type="submit"
              class="btn btn-secondary btn-sm"
            >
              <span class="hero-funnel h-4 w-4" aria-hidden="true"></span> Apply
            </button>
            <a
              id="admin-runtime-clear-filters"
              :href="filters.clear_href"
              data-phx-link="patch"
              data-phx-link-state="push"
              class="btn btn-ghost btn-sm"
            >
              <span class="hero-x-mark h-4 w-4" aria-hidden="true"></span> Clear
            </a>
          </div>
        </form>
      </div>
    </CadencePanel>

    <CadencePanel
      class="card bg-base-200 border border-base-300"
      header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
    >
      <template #header>
        <div>
          <h2 class="text-base font-semibold text-base-content">
            Dashboard Invalidation Decisions
          </h2>
        </div>
      </template>
      <div class="card-body p-0">
        <CadenceTableFrame id="admin-runtime-decisions-table" class="table-sm">
          <thead>
            <tr>
              <th class="hud-label" scope="col">Dashboard</th>
              <th class="hud-label" scope="col">Mission</th>
              <th class="hud-label" scope="col">Source</th>
              <th class="hud-label" scope="col">Boundary</th>
              <th class="hud-label" scope="col">Status</th>
              <th class="hud-label" scope="col">Context</th>
              <th class="hud-label" scope="col">Replay</th>
              <th class="hud-label" scope="col">Refresh</th>
              <th class="hud-label text-right" scope="col">Artifacts</th>
              <th class="hud-label text-right" scope="col">Impacted</th>
              <th class="hud-label" scope="col">Placements</th>
              <th class="hud-label" scope="col">Impact</th>
              <th class="hud-label" scope="col">Observed</th>
              <th class="hud-label text-right" scope="col"><span class="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody id="admin-runtime-decisions-table-body">
            <tr v-if="decisions.length === 0">
              <td colspan="14">
                <div
                  :id="summary.empty_state.id"
                  class="py-6 text-center text-sm text-base-content/70"
                >
                  {{ summary.empty_state.copy }}
                </div>
              </td>
            </tr>
            <tr v-for="decision in decisions" :id="decision.__dom_id" :key="decision.__dom_id">
              <td class="font-mono text-sm">
                <span class="break-all" data-runtime-decision-field="dashboard">
                  {{ decision.dashboard }}
                </span>
              </td>
              <td class="font-mono text-sm">
                <span class="break-all" data-runtime-decision-field="mission">
                  {{ decision.mission }}
                </span>
              </td>
              <td class="font-mono text-sm">
                <span data-runtime-decision-field="source">{{ decision.source }}</span>
              </td>
              <td class="font-mono text-sm">
                <span data-runtime-decision-field="boundary">{{ decision.boundary }}</span>
              </td>
              <td class="font-mono text-sm">
                <span data-runtime-decision-field="status">{{ decision.status }}</span>
              </td>
              <td class="font-mono text-sm">
                <span data-runtime-decision-field="context">{{ decision.context }}</span>
              </td>
              <td class="font-mono text-sm">
                <span class="break-all" data-runtime-decision-field="replay-run">
                  {{ decision.replay_run }}
                </span>
              </td>
              <td class="font-mono text-sm">
                <span data-runtime-decision-field="refresh">{{ decision.refresh }}</span>
              </td>
              <td class="text-right font-mono text-sm">
                <span data-runtime-decision-field="artifacts">{{ decision.artifacts }}</span>
              </td>
              <td class="text-right font-mono text-sm">
                <span data-runtime-decision-field="affected-count">
                  {{ decision.affected_count }}
                </span>
              </td>
              <td class="font-mono text-sm max-w-64">
                <span class="break-all" data-runtime-decision-field="affected-placements">
                  {{ decision.affected_placements }}
                </span>
              </td>
              <td class="font-mono text-sm max-w-56">
                <span class="break-all" data-runtime-decision-field="affected-impact">
                  {{ decision.affected_impact }}
                </span>
              </td>
              <td class="font-mono text-sm">
                <span data-runtime-decision-field="observed">{{ decision.observed }}</span>
              </td>
              <td class="text-right">
                <a
                  :id="decision.inspect_action.id"
                  :href="decision.inspect_action.href"
                  data-phx-link="patch"
                  data-phx-link-state="push"
                  :aria-current="decision.inspect_action.selected ? 'true' : undefined"
                  :class="[
                    'btn btn-xs',
                    decision.inspect_action.selected ? 'btn-secondary' : 'btn-ghost'
                  ]"
                >
                  <span class="hero-magnifying-glass h-3.5 w-3.5" aria-hidden="true"></span>
                  Inspect
                </a>
              </td>
            </tr>
          </tbody>
        </CadenceTableFrame>
      </div>
    </CadencePanel>

    <div
      v-if="selection.missing"
      id="admin-runtime-decision-detail-missing"
      class="rounded border border-warning/40 bg-warning/10 px-4 py-3 text-sm text-warning-content"
      role="status"
    >
      The selected decision could not be found in durable runtime decision history.
    </div>

    <div
      v-if="selection.outside_results && selection.context_href"
      id="admin-runtime-decision-detail-outside-results"
      class="rounded border border-info/40 bg-info/10 px-4 py-3 text-sm text-base-content"
      :data-runtime-selected-decision-key="selection.decision_key"
      :data-runtime-selected-decision-context-link="selection.context_href"
      role="status"
    >
      <div class="flex flex-wrap items-center justify-between gap-3">
        <span>
          The selected decision was loaded directly and is outside the current filtered result set.
        </span>
        <a
          id="admin-runtime-show-selected-context"
          :href="selection.context_href"
          data-phx-link="patch"
          data-phx-link-state="push"
          class="btn btn-secondary btn-xs"
        >
          <span class="hero-funnel h-3.5 w-3.5" aria-hidden="true"></span>
          Show in table context
        </a>
      </div>
    </div>

    <CadencePanel
      v-if="selection.detail"
      :id="selection.detail.id"
      class="card bg-base-200 border border-base-300"
      header-class="flex items-start justify-between gap-4 border-b border-base-300 px-4 py-3"
    >
      <template #header>
        <div>
          <h2 class="text-base font-semibold text-base-content">Decision Detail</h2>
          <p class="mt-1 text-xs text-base-content/70">{{ selection.detail.subtitle }}</p>
        </div>
        <div class="flex items-center gap-2">
          <a
            :id="selection.detail.close_action.id"
            :href="selection.detail.close_action.href"
            data-phx-link="patch"
            data-phx-link-state="push"
            class="btn btn-ghost btn-xs"
          >
            <span class="hero-x-mark h-3.5 w-3.5" aria-hidden="true"></span> Close
          </a>
        </div>
      </template>
      <div class="card-body p-6">
        <div
          :id="selection.detail.evidence.id"
          class="grid gap-x-8 gap-y-6 lg:grid-cols-2 xl:grid-cols-4"
          :data-runtime-decision-detail-key="selection.detail.evidence.decision_key"
          :data-runtime-decision-detail-source="selection.detail.evidence.source"
        >
          <div
            v-for="group in selection.detail.evidence.groups"
            :key="group.key"
            class="space-y-3 border-t border-base-300 pt-3"
          >
            <p class="hud-label">{{ group.label }}</p>
            <div class="min-w-0">
              <CadenceDataRow
                v-for="fact in group.facts"
                :key="fact.key"
                row-class="hud-data-row"
                label-class="hud-data-label"
                :label="fact.label"
              >
                <span class="hud-data-value">
                  <span
                    class="break-all"
                    :data-runtime-decision-detail-field="fact.key"
                  >{{ fact.value }}</span>
                </span>
              </CadenceDataRow>
            </div>
          </div>
        </div>

        <div class="mt-6 grid gap-6 lg:grid-cols-3">
          <div
            v-for="section in selection.detail.sections"
            :key="section.key"
            class="min-w-0 border-t border-base-300 pt-3"
          >
            <p class="hud-label">{{ section.label }}</p>
            <div :id="section.id" class="mt-3">
              <CadenceDataRow
                v-for="pair in section.pairs"
                :key="pair.key"
                row-class="hud-data-row"
                label-class="hud-data-label"
                :label="pair.label"
              >
                <span class="hud-data-value">
                  <span class="break-all">{{ pair.value }}</span>
                </span>
              </CadenceDataRow>
              <p v-if="section.pairs.length === 0" class="text-sm text-base-content/60">
                {{ section.empty_copy }}
              </p>
            </div>
          </div>
        </div>
      </div>
    </CadencePanel>
  </div>
</template>
