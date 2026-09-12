<script setup lang="ts">
import { computed, onBeforeUnmount, reactive, ref, useId, watch } from "vue";
import type { OpsPageContext, OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import type { WorkspaceSnapshot } from "./contracts";
import WorkspaceSnapshotCanvas from "./WorkspaceSnapshotCanvas.vue";

const props = defineProps<{
  model: WorkspaceSnapshot;
  context: OpsPageContext;
  port: OpsPagePort;
  refresh: () => Promise<void>;
}>();
const instanceId = `dashboard-viewer-${useId().replaceAll(/[^a-zA-Z0-9_-]/g, "-")}`;
const directory = computed(
  () => `/missions/${encodeURIComponent(props.model.mission_id)}/ops/dashboards`,
);
const base = computed(() => `${directory.value}/${encodeURIComponent(props.model.dashboard_id)}`);
const diagnostics = computed(() => {
  const context = props.model.context;
  if (context.time_mode === "replay_run") return null;
  const query = new URLSearchParams({
    time_mode: context.time_mode,
    time_axis: context.time_axis,
    realm: context.realm,
    selection_view: context.data_view,
    limit_mode: context.limit_mode,
  });
  if (context.time_mode !== "live") {
    if (!context.from || !context.to) return null;
    query.set("from", context.from);
    query.set("to", context.to);
  }
  return `${base.value}/diagnostics?${query}`;
});
const draft = reactive({
  mode: "live",
  axis: "generation_time",
  from: "",
  to: "",
  realm: "flight",
  view: "canonical",
  limits: "observed",
});
watch(
  () => props.model.context,
  (context) => {
    Object.assign(draft, {
      mode: context.time_mode,
      axis: context.time_axis,
      from: context.from ?? "",
      to: context.to ?? "",
      realm: context.realm,
      view: context.data_view,
      limits: context.limit_mode,
    });
  },
  { immediate: true },
);
const error = ref("");
const refreshing = ref(false);
let disposed = false;
onBeforeUnmount(() => {
  disposed = true;
});
function timestampMicros(value: string): bigint | null {
  const match = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,6}))?(Z|[+-]\d{2}:\d{2})$/.exec(
    value,
  );
  if (!match) return null;
  const calendar = Date.parse(`${match[1]}Z`),
    instant = Date.parse(match[1] + match[3]);
  if (
    !Number.isFinite(calendar) ||
    !Number.isFinite(instant) ||
    new Date(calendar).toISOString().slice(0, 19) !== match[1]
  )
    return null;
  return BigInt(instant) * 1000n + BigInt((match[2] ?? "").padEnd(6, "0"));
}
function applyContext() {
  error.value = "";
  if (refreshing.value || disposed) return;
  if (["range", "archive"].includes(draft.mode)) {
    const from = timestampMicros(draft.from),
      to = timestampMicros(draft.to);
    if (from === null || to === null || to <= from || to - from > 31n * 86400000000n) {
      error.value =
        "Enter ISO timestamps with a timezone and an increasing range of at most 31 days.";
      return;
    }
  }
  const query = new URLSearchParams({
    time_mode: draft.mode,
    time_axis: draft.axis,
    realm: draft.realm,
    selection_view: draft.view,
    limit_mode: draft.limits,
  });
  if (["range", "archive"].includes(draft.mode)) {
    // Preserve timezone and fractional precision for Phoenix's exact parser.
    // Date's millisecond normalization must not alter a requested boundary.
    query.set("from", draft.from);
    query.set("to", draft.to);
  }
  props.port.navigate(`${base.value}?${query}`);
}
async function refresh() {
  if (refreshing.value || disposed) return;
  refreshing.value = true;
  error.value = "";
  try {
    await props.refresh();
  } catch {
    if (!disposed) error.value = "The snapshot could not be refreshed. Try again.";
  } finally {
    if (!disposed) refreshing.value = false;
  }
}
</script>

<template>
  <main id="dashboard-workspace-feature" class="space-y-4 min-w-0" :aria-busy="refreshing">
    <CadencePageHeading>
      <template #eyebrow>OPS / DASHBOARDS</template>
      <template #title
        ><span id="dashboard-viewer-title">{{ model.name }}</span></template
      >
      <template #description>{{ model.description ?? "" }}</template>
    </CadencePageHeading>
    <div class="flex flex-wrap items-center justify-between gap-3 border-y border-base-300 py-3">
      <div class="text-xs font-mono text-base-content/65">
        <span id="dashboard-viewer-version">Published v{{ model.document_version }}</span>
        <span class="mx-2" aria-hidden="true">/</span>
        <span id="dashboard-viewer-delivery">Snapshot · refresh to update</span>
      </div>
      <nav aria-label="Dashboard actions" class="flex flex-wrap gap-2">
        <a
          v-if="diagnostics"
          id="dashboard-viewer-diagnostics"
          :href="diagnostics"
          class="btn btn-sm btn-ghost"
          title="Inspect the current publication with this runtime context; this does not reconstruct the displayed snapshot"
          >Execution diagnostics</a
        >
        <span
          v-else
          id="dashboard-viewer-diagnostics-unavailable"
          class="self-center text-xs text-base-content/60"
          >Diagnostics context is not supported.</span
        >
        <a id="dashboard-viewer-directory" :href="directory" class="btn btn-sm btn-ghost"
          >All dashboards</a
        >
        <a id="dashboard-viewer-activity" :href="`${base}/activity`" class="btn btn-sm btn-ghost"
          >Activity</a
        >
        <a
          v-if="model.author"
          id="dashboard-viewer-edit"
          :href="`${base}/edit`"
          class="btn btn-sm btn-ghost"
          >Edit draft</a
        >
        <button
          id="dashboard-viewer-refresh"
          type="button"
          class="btn btn-sm btn-outline"
          :disabled="refreshing"
          @click="refresh"
        >
          {{ refreshing ? "Refreshing…" : "Refresh snapshot" }}
        </button>
      </nav>
    </div>
    <details id="dashboard-viewer-context" class="rounded-lg border border-base-300 bg-base-200/40">
      <summary class="cursor-pointer px-4 py-3 text-xs font-mono">
        {{ model.context.time_mode }} / {{ model.context.time_axis.replaceAll("_", " ") }} /
        {{ model.context.realm }} / {{ model.context.data_view.replaceAll("_", " ") }} /
        {{ model.context.limit_mode }} limits
      </summary>
      <form
        id="dashboard-viewer-context-form"
        class="flex flex-wrap items-end gap-3 border-t border-base-300 p-4"
        @submit.prevent="applyContext"
      >
        <label class="grid gap-1 text-xs" for="dashboard-viewer-mode"
          >Time mode
          <select
            id="dashboard-viewer-mode"
            v-model="draft.mode"
            class="select select-sm select-bordered"
          >
            <option value="live">Latest snapshot</option>
            <option value="range">Range</option>
            <option value="archive">Archive</option>
            <option v-if="draft.mode === 'replay_run'" value="replay_run" disabled>
              Replay run
            </option>
          </select>
        </label>
        <label class="grid gap-1 text-xs" for="dashboard-viewer-axis"
          >Time axis
          <select
            id="dashboard-viewer-axis"
            v-model="draft.axis"
            class="select select-sm select-bordered"
          >
            <option value="generation_time">Generation time</option>
            <option value="receipt_time">Receipt time</option>
          </select>
        </label>
        <template v-if="['range', 'archive'].includes(draft.mode)">
          <label class="grid gap-1 text-xs" for="dashboard-viewer-from"
            >From (ISO timestamp)
            <input
              id="dashboard-viewer-from"
              v-model="draft.from"
              required
              maxlength="40"
              class="input input-sm input-bordered w-64 max-w-full"
              placeholder="2026-09-07T00:00:00Z"
            />
          </label>
          <label class="grid gap-1 text-xs" for="dashboard-viewer-to"
            >To (ISO timestamp)
            <input
              id="dashboard-viewer-to"
              v-model="draft.to"
              required
              maxlength="40"
              class="input input-sm input-bordered w-64 max-w-full"
              placeholder="2026-09-07T01:00:00Z"
            />
          </label>
        </template>
        <label class="grid gap-1 text-xs" for="dashboard-viewer-realm"
          >Realm
          <select
            id="dashboard-viewer-realm"
            v-model="draft.realm"
            class="select select-sm select-bordered"
          >
            <option
              v-for="realm in ['flight', 'rehearsal', 'replay', 'simulation']"
              :key="realm"
              :value="realm"
            >
              {{ realm }}
            </option>
          </select>
        </label>
        <label class="grid gap-1 text-xs" for="dashboard-viewer-data-view"
          >Data view
          <select
            id="dashboard-viewer-data-view"
            v-model="draft.view"
            class="select select-sm select-bordered"
          >
            <option
              v-for="view in ['canonical', 'as_recorded', 'all_revisions', 'recomputed']"
              :key="view"
              :value="view"
            >
              {{ view.replaceAll("_", " ") }}
            </option>
          </select>
        </label>
        <label class="grid gap-1 text-xs" for="dashboard-viewer-limit-mode"
          >Limit semantics
          <select
            id="dashboard-viewer-limit-mode"
            v-model="draft.limits"
            class="select select-sm select-bordered"
          >
            <option
              v-for="mode in ['observed', 'current', 'recomputed', 'compare']"
              :key="mode"
              :value="mode"
            >
              {{ mode }}
            </option>
          </select>
        </label>
        <button
          id="dashboard-viewer-apply"
          type="submit"
          class="btn btn-sm btn-primary"
          :disabled="refreshing || draft.mode === 'replay_run'"
        >
          Apply context
        </button>
        <a id="dashboard-viewer-reset" :href="base" class="btn btn-sm btn-ghost"
          >Document defaults</a
        >
      </form>
    </details>
    <p v-if="error" id="dashboard-viewer-error" role="alert" class="text-sm text-error">
      {{ error }}
    </p>
    <WorkspaceSnapshotCanvas :snapshot="model" :context="context" :instance-id="instanceId" />
  </main>
</template>
