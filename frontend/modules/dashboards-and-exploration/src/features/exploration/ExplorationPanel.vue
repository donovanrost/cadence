<script setup lang="ts">
import { computed, onBeforeUnmount, reactive, ref, watch } from "vue";
import type { OpsPageContext, OpsPageNavigationPort } from "@cadence/plugin-sdk/ops-pages";
import type { ExplorationQuery, ExplorationRow } from "./contracts";
import { defaults, explorationHref, options, queryKeys } from "./query";
import { readExploration } from "./validation";
import { sameInstant } from "./sample-validation";
import SampleInspection from "./SampleInspection.vue";
const props = defineProps<{
  model: unknown;
  context: OpsPageContext;
  port: OpsPageNavigationPort;
  refresh: () => Promise<void>;
}>();
const model = computed(() => readExploration(props.model, props.context));
const originHref = computed(() => {
  const value = model.value;
  if (value.origin.status !== "ready" || failed.value) return null;
  return `/missions/${encodeURIComponent(value.mission_id)}/ops/dashboards/${encodeURIComponent(value.origin.dashboard.id)}`;
});
const filters = reactive<ExplorationQuery>({});
const pending = ref(false),
  failed = ref(false),
  notice = ref("");
let disposed = false;
watch(
  model,
  (value) => {
    for (const key of Object.keys(filters)) delete filters[key];
    Object.assign(filters, defaults, value.query);
    if (value.query.time_mode === "replay_run" && !value.query.realm) filters.realm = "replay";
    failed.value = false;
  },
  { immediate: true },
);
watch(
  () => props.port,
  (port, _previous, onCleanup) => {
    const disposeGuard = port.guardNavigation?.(() => !pending.value);
    if (disposeGuard) onCleanup(disposeGuard);
  },
  { immediate: true },
);
onBeforeUnmount(() => {
  disposed = true;
});
const advanced = [
  ["logical_source", "Logical source"],
  ["realm", "Data realm"],
  ["replay_run_id", "Replay run ID"],
  ["data_source_id", "Data source ID"],
  ["source_binding_id", "Source binding ID"],
  ["scope_kind", "Scope kind"],
  ["scope_id", "Scope ID"],
  ["spacecraft_id", "Spacecraft filter"],
  ["validity_state", "Validity state"],
  ["limit_mode", "Limit semantics"],
] as const;
const bounded = computed(() =>
  ["range", "archive", "replay_run"].includes(filters.time_mode ?? ""),
);
const messages: Record<string, string> = {
  point_required: "Enter a telemetry point ID to start an investigation.",
  empty: "The selected source returned no observations for this query.",
  unavailable: "This query could not be resolved. Check its source and the diagnostics below.",
  unsupported_exploration_source:
    "This source does not yet support the Explore query contract. No query was executed.",
  unsupported_exploration_scope:
    "This scope cannot currently be applied to this source. No broader query was executed.",
};
function label(value: string) {
  return value ? value.replaceAll("_", " ") : "Not specified";
}
function openOrigin(event: MouseEvent) {
  if (pending.value || disposed || !originHref.value) {
    event.preventDefault();
    return;
  }
  if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)
    return;
  event.preventDefault();
  props.port.navigate(originHref.value);
}
function apply() {
  if (pending.value || disposed) return;
  const query: ExplorationQuery = {};
  for (const key of queryKeys) if (filters[key]) query[key] = filters[key];
  if (!bounded.value && query.time_mode !== "live") {
    delete query.from;
    delete query.to;
  }
  if (query.point_id !== model.value.query.point_id) {
    delete query.sample_id;
    delete query.selected_time;
    delete query.selected_data_source_id;
    delete query.selected_source_binding_id;
  }
  try {
    props.port.navigate(explorationHref(model.value, query));
    notice.value = "";
  } catch {
    notice.value = "Check the query fields. The query was not submitted.";
  }
}
function select(row: ExplorationRow) {
  if (pending.value || !row.sample_id || disposed) return;
  const query: ExplorationQuery = { ...model.value.query, sample_id: row.sample_id };
  delete query.selected_data_source_id;
  delete query.selected_source_binding_id;
  if (row.source.data_source_id && row.source.source_binding_id) {
    query.selected_data_source_id = row.source.data_source_id;
    query.selected_source_binding_id = row.source.source_binding_id;
  }
  delete query.selected_time;
  if (row.axis === "receipt_time" && row.time) query.selected_time = row.time;
  // Freeze the executed window when following a result identity.
  const time = model.value.effective_time;
  if (time?.from && time.to)
    Object.assign(query, { time_mode: time.mode, from: time.from, to: time.to });
  props.port.navigate(explorationHref(model.value, query));
}
function clearSelection() {
  const query = { ...model.value.query };
  delete query.sample_id;
  delete query.selected_time;
  delete query.selected_data_source_id;
  delete query.selected_source_binding_id;
  if (!pending.value) props.port.navigate(explorationHref(model.value, query));
}
function selectedRow(row: ExplorationRow) {
  const query = model.value.query;
  return (
    !!row.sample_id &&
    row.sample_id === query.sample_id &&
    (!query.selected_data_source_id ||
      row.source.data_source_id === query.selected_data_source_id) &&
    (!query.selected_source_binding_id ||
      row.source.source_binding_id === query.selected_source_binding_id) &&
    (!query.selected_time ||
      row.axis !== "receipt_time" ||
      sameInstant(row.time, query.selected_time))
  );
}
async function reload() {
  if (pending.value || disposed) return;
  const previous = props.model;
  pending.value = true;
  try {
    await props.refresh();
    if (!disposed && props.model === previous) throw Error("No refreshed result");
  } catch {
    if (!disposed) failed.value = true;
  } finally {
    if (!disposed) pending.value = false;
  }
}
</script>
<template>
  <section id="exploration-feature" class="space-y-5 p-4 lg:p-6" :aria-busy="pending">
    <header class="flex flex-wrap items-start justify-between gap-3 border-b border-base-300 pb-4">
      <div>
        <p class="text-xs uppercase tracking-widest text-base-content/60">
          Telemetry investigation
        </p>
        <h1 class="mt-1 text-2xl font-semibold">Explore</h1>
        <p class="mt-1 text-sm text-base-content/70">
          Inspect source observations without saving a dashboard.
        </p>
      </div>
      <button
        id="exploration-reload"
        class="btn btn-sm"
        type="button"
        :disabled="pending"
        @click="reload"
      >
        {{ pending ? "Reading…" : "Read again" }}
      </button>
    </header>
    <aside
      v-if="!failed && model.origin.status !== 'not_provided'"
      id="exploration-origin"
      class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 border-l-2 border-base-300 pl-3 text-sm"
      aria-label="Investigation origin"
    >
      <template v-if="model.origin.status === 'ready' && originHref">
        <p class="min-w-0 break-words text-base-content/70">
          Source dashboard:
          <span class="font-medium text-base-content">{{ model.origin.dashboard.name }}</span>
        </p>
        <a
          id="exploration-open-origin"
          :href="originHref"
          class="link shrink-0 text-primary"
          :aria-disabled="pending || undefined"
          :tabindex="pending ? -1 : undefined"
          @click="openOrigin"
          >Open source dashboard</a
        >
        <p class="w-full text-xs text-base-content/60">
          Opens its published view with dashboard defaults. Explore filters are not applied.
        </p>
      </template>
      <p v-else id="exploration-origin-unavailable" class="text-base-content/60" role="status">
        The source dashboard is unavailable. This investigation remains available.
      </p>
    </aside>
    <form id="exploration-query" class="space-y-3" @submit.prevent="apply">
      <fieldset :disabled="pending" class="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <legend class="sr-only">Exploration query</legend>
        <label class="space-y-1 sm:col-span-2">
          <span class="block text-xs font-medium">Point ID</span>
          <input
            id="exploration-point-id"
            v-model="filters.point_id"
            class="input w-full font-mono"
            maxlength="256"
            placeholder="e.g. HK.battery_voltage"
            autocomplete="off"
          />
        </label>
        <label
          v-for="[key, title] in [
            ['time_mode', 'Time window'],
            ['time_axis', 'Time axis'],
            ['selection_view', 'Revision view'],
            ['order', 'Order'],
          ]"
          :key="key"
          class="space-y-1"
        >
          <span class="block text-xs font-medium">{{ title }}</span>
          <select :id="`exploration-${key}`" v-model="filters[key]" class="select w-full">
            <option v-for="value in options[key]" :key="value" :value="value">
              {{ label(value) }}
            </option>
          </select>
        </label>
        <label class="space-y-1"
          ><span class="block text-xs font-medium">Row limit</span
          ><input
            id="exploration-limit"
            v-model="filters.limit"
            class="input w-full"
            type="number"
            min="1"
            max="1000"
            step="1"
            required
        /></label>
        <div class="flex items-end">
          <button id="exploration-apply" class="btn btn-primary w-full" type="submit">
            Run query
          </button>
        </div>
        <template v-if="bounded || filters.time_mode === 'live'">
          <label v-for="key in ['from', 'to']" :key="key" class="space-y-1 sm:col-span-2"
            ><span class="block text-xs font-medium">{{
              key === "from" ? "From (ISO timestamp)" : "To (ISO timestamp)"
            }}</span
            ><input
              :id="`exploration-${key}`"
              v-model="filters[key]"
              class="input w-full font-mono"
              :required="bounded"
              maxlength="40"
              placeholder="2026-09-07T12:00:00.000000Z"
          /></label>
        </template>
      </fieldset>
      <details class="rounded border border-base-300 bg-base-200/30">
        <summary class="cursor-pointer px-3 py-2 text-sm font-medium">Source and scope</summary>
        <fieldset
          :disabled="pending"
          class="grid grid-cols-1 gap-3 p-3 sm:grid-cols-2 xl:grid-cols-3"
        >
          <legend class="sr-only">Source and scope selectors</legend>
          <label v-for="[key, title] in advanced" :key="key" class="space-y-1"
            ><span class="block text-xs font-medium">{{ title }}</span>
            <select
              v-if="options[key]"
              :id="`exploration-${key}`"
              v-model="filters[key]"
              class="select w-full"
            >
              <option v-for="value in options[key]" :key="value" :value="value">
                {{ label(value) }}
              </option>
            </select>
            <input
              v-else
              :id="`exploration-${key}`"
              v-model="filters[key]"
              class="input w-full font-mono"
              maxlength="256"
            />
          </label>
        </fieldset>
      </details>
    </form>
    <p v-if="notice" id="exploration-form-notice" role="alert" class="text-sm text-warning">
      {{ notice }}
    </p>
    <div
      v-if="failed"
      id="exploration-refresh-failed"
      role="alert"
      class="border-l-2 border-warning bg-base-200 p-4"
    >
      The refreshed result could not be confirmed. Read again to load currently authorized
      observations.
    </div>
    <template v-else>
      <div class="flex flex-wrap items-center justify-between gap-2 text-xs text-base-content/70">
        <span id="exploration-row-count">{{ model.rows.length }} observations returned</span>
        <span
          >Read at
          <time id="exploration-loaded-at" :datetime="model.loaded_at" class="font-mono">{{
            model.loaded_at
          }}</time></span
        >
      </div>
      <p
        v-if="model.effective_time?.from"
        id="exploration-window"
        class="break-all font-mono text-xs text-base-content/70"
      >
        {{ model.effective_time.from }} → {{ model.effective_time.to }} · requested
        {{ label(model.effective_time.axis) }}
      </p>
      <SampleInspection
        v-if="model.query.sample_id"
        :inspection="model.inspection"
        :sample-id="model.query.sample_id"
        :pending="pending"
        @clear="clearSelection"
      />
      <p
        v-if="model.status !== 'ready'"
        id="exploration-result-state"
        role="status"
        class="border border-base-300 bg-base-200/30 p-5 text-sm"
      >
        {{ messages[model.status] }}
      </p>
      <p v-if="model.limited" id="exploration-limited" role="status" class="text-sm text-warning">
        The result limit was reached; more observations may exist. Narrow the window or increase the
        row limit.
      </p>
      <ul
        v-if="model.warnings.length"
        id="exploration-warnings"
        class="space-y-1 border-l-2 border-warning p-3 text-xs"
        aria-label="Query diagnostics"
      >
        <li v-for="warning in model.warnings" :key="`${warning.code}:${warning.severity}`">
          <span class="uppercase">{{ warning.severity }}</span> · <code>{{ warning.code }}</code>
        </li>
      </ul>
      <p v-if="model.warnings_limited" class="text-xs text-warning">
        Additional query warnings were omitted.
      </p>
      <div v-if="model.rows.length" class="overflow-x-auto rounded border border-base-300">
        <table id="exploration-results" class="table table-sm w-full">
          <caption class="sr-only">
            Telemetry observations from the executed query
          </caption>
          <thead>
            <tr>
              <th scope="col">Observation time</th>
              <th scope="col">Value</th>
              <th scope="col">Sample identity</th>
              <th scope="col">Source / binding</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in model.rows"
              :key="row.key"
              :data-observation-key="row.key"
              :class="{ 'bg-primary/10': selectedRow(row) }"
            >
              <td>
                <time
                  v-if="row.time"
                  :datetime="row.time"
                  class="whitespace-nowrap font-mono text-xs"
                  >{{ row.time }}</time
                ><span v-else>Not recorded</span
                ><span class="block text-xs text-base-content/60">{{ label(row.axis) }}</span>
              </td>
              <td class="font-mono">
                {{ row.value === null ? "Not recorded" : row.value === "" ? "Empty" : row.value }}
                <span class="text-base-content/60">{{ row.unit }}</span>
              </td>
              <td>
                <button
                  v-if="row.sample_id"
                  class="btn btn-xs btn-ghost max-w-64 truncate font-mono"
                  type="button"
                  :disabled="pending"
                  :title="row.sample_id"
                  @click="select(row)"
                >
                  {{ row.sample_id }}</button
                ><span v-else class="text-xs text-base-content/60">No physical sample ID</span>
              </td>
              <td class="font-mono text-xs">
                <span class="block break-all">{{
                  row.source.data_source_id ?? "Not recorded"
                }}</span
                ><span class="block break-all text-base-content/60">{{
                  row.source.source_binding_id ?? "Not recorded"
                }}</span
                ><span
                  >{{ row.source.realm
                  }}<template v-if="row.source.dataset"> · {{ row.source.dataset }}</template></span
                >
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </section>
</template>
