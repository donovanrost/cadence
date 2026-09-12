<script setup lang="ts">
import { computed, ref, watch } from "vue";
import type { OpsPageContext } from "@cadence/plugin-sdk/ops-pages";
import DiagnosticIdentity from "./DiagnosticIdentity.vue";
import { readExecutionDiagnostics } from "./validation";
import {
  collectionLabels,
  matchingRows,
  readSelection,
  type DiagnosticSelection,
} from "./selection";

const props = defineProps<{
  model: unknown;
  context: OpsPageContext;
  selection: DiagnosticSelection;
}>();
const emit = defineEmits<{ select: [selection: DiagnosticSelection] }>();
const model = computed(() => readExecutionDiagnostics(props.model, props.context));
const selection = computed(() => readSelection(props.selection));
const collection = computed(() =>
  model.value.collections.find((c) => c.id === selection.value.collection)!,
);
const rows = computed(() => matchingRows(collection.value.rows, selection.value.filter));
const selected = computed(() =>
  collection.value.rows.find((row) => row.id === selection.value.row),
);
const outsideFilter = computed(
  () => selected.value && !rows.value.some((row) => row.id === selected.value?.id),
);
const filter = ref(selection.value.filter);
const filterError = ref("");
watch(
  () => props.selection,
  () => {
    filter.value = selection.value.filter;
    filterError.value = "";
  },
);
function applyFilter() {
  try {
    const next = readSelection({ ...selection.value, filter: filter.value });
    filterError.value = "";
    emit("select", next);
  } catch {
    filterError.value = "Use at most 256 UTF-8 bytes with no control characters.";
  }
}
const label = (key: string) => key.replaceAll("_", " ");
const scalar = (value: string | number | boolean | null) =>
  value === null ? "Not recorded" : value === "" ? "Empty" : String(value);
const provenance = computed(() => {
  switch (collection.value.source) {
    case "inspection":
      return "Read-time inspection";
    case "durable":
      return "Durable decision history";
    case "process_local":
      return "Process-local decision history";
    default:
      return "Evidence unavailable";
  }
});
</script>
<template>
  <section id="execution-diagnostics-feature" class="space-y-5 p-4 lg:p-6">
    <header class="border-b border-base-300 pb-5">
      <p class="font-mono text-xs uppercase tracking-widest text-base-content/60">
        Ops / Execution diagnostics
      </p>
      <h1 class="mt-2 text-2xl font-semibold">{{ model.name }}</h1>
      <p class="mt-2 text-sm text-base-content/70">
        Published definition <span class="font-mono">v{{ model.document_version }}</span> · Loaded
        <time id="diagnostics-loaded-at" class="font-mono" :datetime="model.loaded_at">{{
          model.loaded_at
        }}</time>
      </p>
      <p id="diagnostics-evidence-scope" class="mt-3 max-w-3xl text-sm text-base-content/70">
        Plan, requests, frames, cache and source execution describe an inspection performed when
        this evidence was loaded. They do not reconstruct an earlier viewer session. Refresh and
        invalidation show separately recorded decisions.
      </p>
    </header>
    <div class="grid items-start gap-5 xl:grid-cols-[14rem_minmax(0,1fr)]">
      <nav aria-label="Diagnostic collections" class="border border-base-300">
        <h2
          class="border-b border-base-300 px-4 py-3 text-xs font-semibold uppercase tracking-wide"
        >
          Evidence collections
        </h2>
        <ul class="grid grid-cols-2 sm:grid-cols-3 xl:grid-cols-1">
          <li v-for="item in model.collections" :key="item.id" class="min-w-0">
            <button
              :id="`diagnostics-collection-${item.id}`"
              type="button"
              class="flex w-full items-center justify-between gap-2 border-l-2 p-3 text-left text-sm hover:bg-base-200"
              :class="
                item.id === selection.collection
                  ? 'border-primary bg-primary/5'
                  : 'border-transparent'
              "
              :aria-current="item.id === selection.collection ? 'true' : undefined"
              @click="emit('select', { collection: item.id, row: null, filter: selection.filter })"
            >
              <span>{{ collectionLabels[item.id] }}</span>
              <span class="font-mono text-xs text-base-content/60">{{
                item.state === "unavailable" ? "—" : `${item.rows.length}${item.limited ? "+" : ""}`
              }}</span>
            </button>
          </li>
        </ul>
      </nav>
      <div class="min-w-0 space-y-4">
        <div class="flex flex-wrap items-baseline justify-between gap-2">
          <h2 id="diagnostics-collection-title" class="text-lg font-semibold">
            {{ collectionLabels[collection.id] }}
          </h2>
          <p id="diagnostics-provenance" class="font-mono text-xs text-base-content/60">
            {{ provenance }}
          </p>
        </div>
        <p
          v-if="collection.source === 'process_local'"
          id="diagnostics-local-warning"
          class="border-l-2 border-warning bg-base-200 p-3 text-sm"
        >
          No durable decisions were found. These scoped records are retained only in the current
          runtime process and can disappear after restart.
        </p>
        <p
          v-if="collection.state === 'unavailable'"
          id="diagnostics-unavailable"
          role="status"
          class="border-l-2 border-warning bg-base-200 p-4 text-sm"
        >
          This evidence could not be loaded. This is not an empty or successful result. Other
          collections remain available.
        </p>
        <template v-else>
          <form
            id="diagnostics-filter-form"
            class="flex flex-wrap items-end gap-2"
            @submit.prevent="applyFilter"
          >
            <div class="min-w-0 flex-1">
              <label for="diagnostics-filter" class="mb-1 block text-xs text-base-content/70"
                >Filter loaded rows</label
              >
              <input
                id="diagnostics-filter"
                v-model="filter"
                class="input w-full"
                type="search"
                maxlength="256"
                :aria-invalid="filterError ? 'true' : undefined"
                :aria-describedby="filterError ? 'diagnostics-filter-error' : undefined"
              />
            </div>
            <button id="diagnostics-apply-filter" type="submit" class="btn btn-sm">
              Apply filter
            </button>
            <button
              v-if="selection.filter"
              id="diagnostics-clear-filter"
              type="button"
              class="btn btn-sm btn-ghost"
              @click="emit('select', { ...selection, filter: '' })"
            >
              Clear
            </button>
          </form>
          <p
            v-if="filterError"
            id="diagnostics-filter-error"
            role="alert"
            class="text-sm text-error"
          >
            {{ filterError }}
          </p>
          <p
            v-if="collection.limited"
            id="diagnostics-limited"
            class="text-sm text-base-content/70"
          >
            Only the first 50 distinct rows are loaded. Filtering searches these rows, not the
            complete history.
          </p>
          <div class="grid gap-4 lg:grid-cols-[minmax(12rem,1fr)_minmax(0,2fr)]">
            <section
              class="min-w-0 border border-base-300"
              aria-labelledby="diagnostics-rows-title"
            >
              <h3
                id="diagnostics-rows-title"
                class="border-b border-base-300 p-3 text-xs font-semibold uppercase tracking-wide"
              >
                {{ rows.length }} matching rows
              </h3>
              <ul
                id="diagnostics-rows"
                class="max-h-80 divide-y divide-base-300 overflow-y-auto lg:max-h-[36rem]"
              >
                <li v-for="row in rows" :key="row.id">
                  <button
                    :id="`diagnostics-row-${row.id}`"
                    type="button"
                    class="block w-full border-l-2 p-3 text-left hover:bg-base-200"
                    :class="
                      row.id === selection.row
                        ? 'border-primary bg-primary/5'
                        : 'border-transparent'
                    "
                    :aria-current="row.id === selection.row ? 'true' : undefined"
                    @click="emit('select', { ...selection, row: row.id })"
                  >
                    <span class="block text-sm font-medium">{{ row.title }}</span>
                    <span class="mt-1 block break-all font-mono text-xs text-base-content/70">{{
                      row.identity
                    }}</span>
                    <span class="mt-2 block text-xs text-base-content/60">{{
                      label(row.status)
                    }}</span>
                  </button>
                </li>
              </ul>
              <p
                v-if="!rows.length"
                id="diagnostics-empty"
                class="p-4 text-sm text-base-content/70"
              >
                {{
                  collection.rows.length
                    ? "No loaded rows match this filter."
                    : "No rows were recorded in this collection."
                }}
              </p>
            </section>
            <section
              id="diagnostics-detail"
              class="min-w-0 border border-base-300 p-4"
              aria-labelledby="diagnostics-detail-title"
            >
              <h3 id="diagnostics-detail-title" class="text-base font-semibold">
                {{ selected?.title || "Diagnostic detail" }}
              </h3>
              <template v-if="selected">
                <p
                  v-if="outsideFilter"
                  id="diagnostics-outside-filter"
                  role="status"
                  class="mt-3 border-l-2 border-info p-3 text-sm"
                >
                  The selected row is outside the current filter. Its loaded evidence remains
                  displayed.
                </p>
                <p id="diagnostics-detail-status" class="my-3 text-sm text-base-content/70">
                  Status: {{ label(selected.status) }}
                </p>
                <DiagnosticIdentity :key="selected.id" :identity="selected.identity" />
                <dl class="mt-4 divide-y divide-base-300 border-t border-base-300">
                  <div
                    v-for="detail in selected.details"
                    :key="detail.key"
                    class="grid gap-1 py-3 sm:grid-cols-[minmax(8rem,1fr)_minmax(0,2fr)] sm:gap-4"
                  >
                    <dt class="text-xs capitalize text-base-content/60">{{ label(detail.key) }}</dt>
                    <dd class="break-all font-mono text-xs" :data-diagnostic-field="detail.key">
                      {{ scalar(detail.value) }}
                    </dd>
                  </div>
                </dl>
                <p class="mt-4 text-xs text-base-content/60">
                  Text previews are bounded and may be shortened. The diagnostic identity above is
                  exact.
                </p>
              </template>
              <p
                v-else-if="selection.row"
                id="diagnostics-missing-selection"
                role="status"
                class="mt-3 text-sm text-base-content/70"
              >
                The selected row is not present in this loaded collection. It may be outside the
                result limit or no longer retained; no replacement row has been selected.
              </p>
              <p v-else id="diagnostics-select-prompt" class="mt-3 text-sm text-base-content/70">
                Select a row to inspect its evidence.
              </p>
            </section>
          </div>
        </template>
      </div>
    </div>
  </section>
</template>
