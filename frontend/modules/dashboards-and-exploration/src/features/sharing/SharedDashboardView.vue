<script setup lang="ts">
import { computed, ref, useId } from "vue";
import type { OpsPageContext, OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import { WorkspaceSnapshotCanvas } from "../../workspace";
import type { SharedView } from "./contracts";
defineOptions({ inheritAttrs: false });
const props = defineProps<{
  model: SharedView;
  context: OpsPageContext;
  port: OpsPagePort;
  refresh: () => Promise<void>;
}>();
const refreshing = ref(false),
  error = ref("");
const instanceId = "shared-dashboard-" + useId().replaceAll(/[^a-zA-Z0-9_-]/g, "-");
const directory = computed(
  () => "/missions/" + encodeURIComponent(props.model.mission_id) + "/ops/dashboards",
);
const canvasContext = computed(() => ({ ...props.context, resourceId: props.model.dashboard_id }));
const definition = computed(() =>
  props.model.definition ? JSON.stringify(JSON.parse(props.model.definition.json), null, 2) : "",
);
function navigate(event: MouseEvent, href: string) {
  if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)
    return;
  event.preventDefault();
  props.port.navigate(href);
}
async function reload() {
  if (refreshing.value) return;
  refreshing.value = true;
  error.value = "";
  try {
    await props.refresh();
  } catch {
    error.value =
      "This view could not be refreshed. The displayed values are from the last successful read.";
  } finally {
    refreshing.value = false;
  }
}
</script>
<template>
  <section
    id="shared-dashboard-feature"
    class="min-w-0 space-y-5 p-4 lg:p-6"
    :aria-busy="refreshing"
  >
    <header class="flex flex-wrap items-start justify-between gap-4 border-b border-base-300 pb-5">
      <div class="min-w-0">
        <p class="font-mono text-xs uppercase tracking-widest text-base-content/60">
          Ops / {{ model.kind === "share" ? "Mission share" : "Definition snapshot" }}
        </p>
        <h1 id="shared-view-title" class="mt-2 break-words text-2xl font-semibold">
          {{ model.definition?.name || "Shared dashboard" }}
        </h1>
        <p class="mt-2 text-sm text-base-content/65">{{ model.definition?.description }}</p>
      </div>
      <nav aria-label="Shared dashboard navigation" class="flex flex-wrap gap-2">
        <a
          id="shared-view-directory"
          class="btn btn-sm btn-ghost"
          :href="directory"
          @click="navigate($event, directory)"
          >Dashboards</a
        >
        <button
          id="shared-view-refresh"
          type="button"
          class="btn btn-sm"
          :disabled="refreshing"
          @click="reload"
        >
          {{ refreshing ? "Refreshing…" : "Refresh view" }}
        </button>
      </nav>
    </header>
    <section
      class="grid gap-4 border border-base-300 bg-base-200/20 p-4 sm:grid-cols-3"
      aria-label="Access and definition"
    >
      <div>
        <h2 class="text-xs text-base-content/55">Access</h2>
        <p id="shared-view-visibility" class="mt-1 text-sm">
          {{
            model.data_visibility === "definition_only"
              ? "Definition only · runtime data withheld"
              : "Authorized mission runtime data"
          }}
        </p>
        <p class="mt-1 text-xs text-base-content/55">
          Mission authorization is checked on every read.
        </p>
      </div>
      <div>
        <h2 class="text-xs text-base-content/55">Definition</h2>
        <p id="shared-view-version" class="mt-1 font-mono text-sm">
          {{
            model.definition
              ? (model.kind === "share" ? "Published v" : "Captured v") + model.definition.version
              : "No published definition available"
          }}
        </p>
        <p class="mt-1 text-xs text-base-content/55">
          {{
            model.kind === "share"
              ? "Follows the published dashboard, never its unsaved draft."
              : "Stored definition; later edits and archive do not replace it."
          }}
        </p>
      </div>
      <div>
        <h2 class="text-xs text-base-content/55">
          {{ model.kind === "share" ? "Expiration" : "Captured" }}
        </h2>
        <p id="shared-view-lifetime" class="mt-1 break-words font-mono text-xs">
          {{ model.kind === "share" ? model.expires_at || "No expiration" : model.created_at }}
        </p>
      </div>
    </section>
    <p id="shared-view-semantics" class="border-l-2 border-primary/50 bg-base-200/20 p-3 text-sm">
      {{
        model.data_semantics === "frozen_time_window"
          ? "The time boundaries are fixed, not the telemetry values. Refresh resolves data within the captured window."
          : "Runtime values, when permitted, are a read-time snapshot. This is not a live stream or a frozen copy of telemetry."
      }}
    </p>
    <p id="shared-view-freshness" class="text-xs text-base-content/55">
      Loaded {{ model.loaded_at }}
    </p>
    <p v-if="error" id="shared-view-error" role="alert" class="text-sm text-warning">{{ error }}</p>
    <p
      v-if="!model.definition"
      id="shared-view-unpublished"
      role="status"
      class="border border-warning/40 p-4 text-sm"
    >
      No published dashboard is available for this share. An author must publish an active dashboard
      before it can be viewed here.
    </p>
    <details id="shared-view-context" class="border border-base-300 p-4">
      <summary class="cursor-pointer text-sm font-medium">Stored runtime context</summary>
      <dl v-if="Object.keys(model.runtime_context).length" class="mt-4 grid gap-3 sm:grid-cols-2">
        <div v-for="(value, key) in model.runtime_context" :key="key" class="min-w-0">
          <dt class="font-mono text-xs text-base-content/55">{{ key }}</dt>
          <dd class="mt-1 break-all text-sm">{{ value }}</dd>
        </div>
      </dl>
      <p v-else class="mt-3 text-sm text-base-content/55">
        No additional selection was captured. The definition supplies its defaults.
      </p>
    </details>
    <WorkspaceSnapshotCanvas
      v-if="model.canvas"
      :snapshot="model.canvas"
      :context="canvasContext"
      :instance-id="instanceId"
    />
    <details
      v-if="model.definition"
      id="shared-view-definition"
      class="min-w-0 border border-base-300 p-4"
    >
      <summary class="cursor-pointer text-sm font-medium">
        Complete definition · {{ model.definition.placements }} placements /
        {{ model.definition.sections }} sections
      </summary>
      <pre
        class="mt-4 max-h-[36rem] overflow-auto whitespace-pre-wrap break-all font-mono text-xs"
        >{{ definition }}</pre>
    </details>
  </section>
</template>
