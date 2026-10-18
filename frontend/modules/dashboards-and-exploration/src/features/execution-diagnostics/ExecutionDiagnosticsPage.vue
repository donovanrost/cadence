<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, shallowRef, watch } from "vue";
import type { OpsPageContext, OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import ExecutionDiagnostics from "./ExecutionDiagnostics.vue";
import { diagnosticsHref, exact, readDiagnosticsPage } from "./page-state";
import { readSelection, type DiagnosticSelection } from "./selection";
const props = defineProps<{
  state: unknown;
  context: OpsPageContext;
  port: OpsPagePort;
  refresh: () => Promise<void>;
}>();
const state = shallowRef(readDiagnosticsPage(props.state, props.context));
const pending = ref(false),
  unavailable = ref(false),
  notice = ref("");
let disposed = false,
  disposeGuard: (() => void) | undefined;
watch(
  () => props.state,
  (value) => {
    if (pending.value) return;
    const next = readDiagnosticsPage(value, props.context);
    if (next.sequence < state.value.sequence) return;
    state.value = next;
    unavailable.value = false;
    notice.value = "";
  },
);
onMounted(() => {
  disposeGuard = props.port.guardNavigation?.(() => !pending.value);
});
onBeforeUnmount(() => {
  disposed = true;
  disposeGuard?.();
});
const viewer = computed(() => diagnosticsHref(state.value));
function select(selection: DiagnosticSelection) {
  if (!pending.value && !unavailable.value)
    props.port.navigate(diagnosticsHref(state.value, readSelection(selection)));
}
function navigate(event: MouseEvent) {
  if (pending.value) {
    event.preventDefault();
    return;
  }
  if (event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey)
    return;
  event.preventDefault();
  props.port.navigate(viewer.value);
}
async function inspect() {
  if (pending.value || unavailable.value || disposed) return;
  const previous = state.value;
  pending.value = true;
  notice.value = "";
  try {
    const response = exact(
      await props.port.execute("inspect", { sequence: previous.sequence + 1 }),
      ["status", "state"],
    );
    if (disposed) return;
    if (response.status !== "ok") throw Error("Inspection unavailable");
    const next = readDiagnosticsPage(response.state, props.context);
    if (
      next.sequence !== previous.sequence + 1 ||
      next.publication_changed ||
      next.selection.collection !== previous.selection.collection ||
      next.selection.row !== previous.selection.row ||
      next.selection.filter !== previous.selection.filter ||
      diagnosticsHref(next) !== diagnosticsHref(previous)
    )
      throw Error("Mismatched inspection response");
    state.value = next;
    notice.value =
      "New inspection loaded. This is not a reconstruction of the previous viewer session.";
  } catch {
    if (!disposed) unavailable.value = true;
  } finally {
    if (!disposed) pending.value = false;
  }
}
async function reload() {
  if (pending.value || disposed) return;
  const observedProps = props.state;
  pending.value = true;
  try {
    await props.refresh();
    if (!disposed && props.state !== observedProps) {
      const next = readDiagnosticsPage(props.state, props.context);
      if (next.sequence < state.value.sequence) throw Error("Stale refreshed state");
      state.value = next;
      unavailable.value = false;
    }
  } catch {
    /* The unavailable state remains explicit. */
  } finally {
    if (!disposed) pending.value = false;
  }
}
</script>
<template>
  <section id="execution-diagnostics-page" :aria-busy="pending">
    <nav
      class="flex flex-wrap items-center gap-2 border-b border-base-300 px-4 py-3 lg:px-6"
      aria-label="Diagnostics actions"
    >
      <a
        id="diagnostics-viewer"
        :href="viewer"
        class="btn btn-sm btn-ghost"
        :aria-disabled="pending || undefined"
        @click="navigate"
        >View dashboard</a
      >
      <button
        v-if="!unavailable"
        id="diagnostics-inspect"
        type="button"
        class="btn btn-sm"
        :disabled="pending || state.sequence === 1000000"
        @click="inspect"
      >
        {{ pending ? "Inspecting…" : "Inspect again" }}
      </button>
    </nav>
    <div
      v-if="unavailable"
      id="diagnostics-page-unavailable"
      role="alert"
      class="m-4 border-l-2 border-warning bg-base-200 p-4"
    >
      <p>
        The inspection outcome could not be confirmed. Reload the page to read currently authorized
        evidence.
      </p>
      <button
        id="diagnostics-reload"
        type="button"
        class="btn btn-sm mt-3"
        :disabled="pending"
        @click="reload"
      >
        Reload page
      </button>
    </div>
    <template v-else>
      <p
        v-if="state.publication_changed"
        id="diagnostics-publication-changed"
        role="status"
        class="m-4 border-l-2 border-warning bg-base-200 p-3 text-sm"
      >
        The published definition changed after this inspection. The loaded evidence is retained;
        inspect again to use the current publication.
      </p>
      <p
        v-if="notice"
        id="diagnostics-inspection-notice"
        role="status"
        class="px-4 pt-3 text-sm text-base-content/70"
      >
        {{ notice }}
      </p>
      <fieldset :disabled="pending" class="min-w-0 border-0 p-0">
        <legend class="sr-only">Diagnostics evidence</legend>
        <ExecutionDiagnostics
          :model="state.model"
          :context="context"
          :selection="state.selection"
          @select="select"
        />
      </fieldset>
    </template>
  </section>
</template>
