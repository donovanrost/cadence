<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, useId, watch } from "vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import WorkspaceSnapshotCanvas from "../workspace/WorkspaceSnapshotCanvas.vue";
import WidgetFields from "./WidgetFields.vue";
import ObservablePicker from "./ObservablePicker.vue";
import EditorLayoutCanvas from "./EditorLayoutCanvas.vue";
import RuntimeDefaultsFields from "./RuntimeDefaultsFields.vue";
import { useDashboardEditor, type EditorProps } from "./useDashboardEditor";
const props = defineProps<EditorProps>();
const editor = useDashboardEditor(props);
const {
  state,
  selection,
  selectedPlacement,
  draft,
  dirty,
  unsaved,
  pending,
  gesturing,
  locked,
  notice,
  choose,
  applyChanges,
  saveDraft,
  discardDraft,
  review,
  run,
  reload,
} = editor;
const model = computed(() => state.value.model);
const base = computed(
  () => `/missions/${encodeURIComponent(model.value.mission_id)}/ops/dashboards`,
);
const instanceId = `dashboard-editor-${useId().replaceAll(/[^a-zA-Z0-9_-]/g, "-")}`;
const inspectorTitle = computed(() =>
  selection.value.kind === "metadata"
    ? "Dashboard details"
    : selection.value.kind === "runtime"
      ? "Runtime defaults"
      : selection.value.kind === "layout"
        ? "Widget position"
        : `${selection.value.id ? "Edit" : "Add"} ${selection.value.kind}`,
);
const disabled = computed(() => locked.value || pending.value || gesturing.value);
watch(
  () => props.port,
  (port, _previous, onCleanup) => {
    if (!port.guardNavigation)
      throw Error("The dashboard editor requires host navigation admission.");
    onCleanup(port.guardNavigation(editor.canLeave));
  },
  { immediate: true },
);
function beforeUnload(event: BeforeUnloadEvent) {
  if (unsaved.value || pending.value || gesturing.value) {
    event.preventDefault();
    event.returnValue = "";
  }
}
onMounted(() => {
  window.addEventListener("beforeunload", beforeUnload);
});
onBeforeUnmount(() => {
  editor.dispose();
  window.removeEventListener("beforeunload", beforeUnload);
});
function typeChanged() {
  const current = draft.value;
  if (current.kind !== "widget") return;
  const type = current.fields.type;
  if (["event_timeline", "constellation_health"].includes(type)) {
    current.observables = "";
    current.fields.mode = "context";
    current.fields.binding_source =
      type === "event_timeline" ? "events" : "operational_observables";
  } else {
    if (["events", "limits"].includes(current.fields.binding_source) && type !== "state_timeline")
      current.fields.binding_source = "telemetry";
    if (
      !["time_series", "status_matrix", "data_table"].includes(type) &&
      current.fields.mode === "repeat"
    )
      current.fields.mode = "context";
  }
}
function remove() {
  if (dirty.value || disabled.value || !selection.value.id) return;
  const section = selection.value.kind === "section";
  const message = section
    ? "Remove this section? Its widgets will become unsectioned."
    : "Remove this widget from the draft?";
  if (!window.confirm(message)) return;
  if (section) void run("remove_section", { section_id: selection.value.id });
  else void run("remove_widget", { placement_id: selection.value.id });
}

const layoutFields = [
  ["x", "Column"],
  ["y", "Row"],
  ["w", "Width"],
  ["h", "Height"],
] as const;
</script>
<template>
  <main id="dashboard-editor-feature" class="space-y-4 min-w-0" :aria-busy="pending">
    <CadencePageHeading
      ><template #eyebrow>OPS / DASHBOARD AUTHORING</template
      ><template #title>{{ model.name }}</template
      ><template #description
        >Stage changes here, then save one draft version. Publishing is reviewed in
        Activity.</template
      ></CadencePageHeading
    >
    <div class="flex flex-wrap items-center justify-between gap-3 border-y border-base-300 py-3">
      <div class="flex items-center gap-3 text-xs font-mono">
        <span id="editor-version">Draft v{{ model.document_version }}</span
        ><span
          id="editor-save-state"
          :class="unsaved || locked ? 'text-warning' : 'text-base-content/65'"
          >{{
            pending ? "Working…" : locked ? "Review required" : unsaved ? "Unsaved edits" : "Saved"
          }}</span
        >
      </div>
      <nav aria-label="Dashboard editor actions" class="flex flex-wrap gap-2">
        <button
          id="editor-arrange"
          type="button"
          class="btn btn-sm btn-outline"
          :disabled="disabled || selection.kind === 'arrange'"
          @click="choose('arrange')"
        >
          Arrange layout
        </button>
        <a id="editor-directory" :href="base" class="btn btn-sm btn-ghost">All dashboards</a>
        <a
          id="editor-viewer"
          :href="`${base}/${encodeURIComponent(model.dashboard_id)}`"
          class="btn btn-sm btn-ghost"
          >Published view</a
        >
        <button
          id="editor-reload"
          type="button"
          class="btn btn-sm btn-outline"
          :disabled="pending"
          @click="reload"
        >
          Reload saved draft
        </button>
        <button
          id="editor-save-draft"
          type="button"
          class="btn btn-sm btn-primary"
          :disabled="disabled || !unsaved"
          @click="saveDraft"
        >
          Save draft
        </button>
        <button
          id="editor-discard-draft"
          type="button"
          class="btn btn-sm btn-outline"
          :disabled="disabled || !unsaved"
          @click="discardDraft"
        >
          Discard all changes
        </button>
        <button
          id="editor-review"
          type="button"
          class="btn btn-sm btn-outline"
          :disabled="disabled"
          @click="review"
        >
          Review &amp; publish
        </button>
      </nav>
    </div>
    <p id="editor-staging-state" class="text-xs font-mono text-base-content/60">
      Candidate r{{ state.revision }} · Live updates paused ·
      {{ state.dirty ? "Staged changes are not saved" : "Matches saved draft" }}
    </p>
    <p
      v-if="notice || locked"
      id="editor-outcome"
      role="status"
      class="rounded border border-warning/30 bg-base-200 px-4 py-3 text-sm"
    >
      {{ notice || "A previous operation needs review. Reload the saved draft before continuing." }}
    </p>
    <section v-if="draft.kind === 'arrange'" class="space-y-4 min-w-0">
      <EditorLayoutCanvas
        v-model="draft.layouts"
        :model="model"
        :disabled="locked || pending"
        :instance-id="instanceId"
        @gesture="gesturing = $event"
      />
      <div class="flex flex-wrap gap-2">
        <button
          id="editor-layout-save"
          type="button"
          class="btn btn-sm btn-primary"
          :disabled="disabled || !dirty"
          @click="applyChanges"
        >
          Apply layout to candidate
        </button>
        <button
          id="editor-layout-discard"
          type="button"
          class="btn btn-sm btn-ghost"
          :disabled="disabled || !dirty"
          @click="choose('arrange')"
        >
          Discard layout edits
        </button>
        <button
          id="editor-layout-done"
          type="button"
          class="btn btn-sm btn-outline"
          :disabled="pending || gesturing"
          @click="choose('metadata')"
        >
          Back to details
        </button>
      </div>
    </section>
    <div v-else class="editor-layout">
      <section
        class="min-w-0 rounded-lg border border-base-300 bg-base-200/30"
        aria-labelledby="editor-outline-title"
      >
        <div class="flex flex-wrap items-center justify-between gap-3 border-b border-base-300 p-4">
          <h2 id="editor-outline-title" class="text-xs font-mono uppercase tracking-widest">
            Dashboard outline
          </h2>
          <span class="text-xs text-base-content/65"
            >{{ model.placements.length }} widgets · {{ model.sections.length }} sections</span
          >
        </div>
        <div class="p-3 space-y-3">
          <button
            id="editor-details"
            type="button"
            class="btn btn-sm btn-ghost w-full justify-start"
            :disabled="pending"
            @click="choose('metadata')"
          >
            Dashboard details
          </button>
          <button
            id="editor-runtime"
            type="button"
            class="btn btn-sm btn-ghost w-full justify-start"
            :disabled="pending"
            @click="choose('runtime')"
          >
            Runtime defaults
          </button>
          <div class="grid grid-cols-2 gap-2">
            <button
              id="editor-add-section"
              type="button"
              class="btn btn-sm btn-outline"
              :disabled="disabled"
              @click="choose('section')"
            >
              Add section</button
            ><button
              id="editor-add-widget"
              type="button"
              class="btn btn-sm btn-outline"
              :disabled="disabled"
              @click="choose('widget')"
            >
              Add widget
            </button>
          </div>
          <div
            v-for="section in [...model.sections, { id: null, title: 'Unsectioned' }]"
            :key="section.id ?? 'unsectioned'"
            class="border-t border-base-300 pt-3"
          >
            <div class="flex items-center gap-2 mb-2">
              <button
                v-if="section.id"
                type="button"
                class="btn btn-xs btn-ghost min-w-0 flex-1 justify-start truncate"
                :data-editor-section="section.id"
                :disabled="pending"
                @click="choose('section', section.id)"
              >
                {{ section.title }}
              </button>
              <h3 v-else class="flex-1 px-2 text-xs font-mono text-base-content/65">Unsectioned</h3>
              <template v-if="section.id"
                ><button
                  type="button"
                  class="btn btn-xs btn-ghost"
                  :aria-label="`Move ${section.title} up`"
                  :disabled="disabled || dirty || model.sections[0]?.id === section.id"
                  @click="run('move_section', { section_id: section.id, direction: 'up' })"
                >
                  ↑</button
                ><button
                  type="button"
                  class="btn btn-xs btn-ghost"
                  :aria-label="`Move ${section.title} down`"
                  :disabled="disabled || dirty || model.sections.at(-1)?.id === section.id"
                  @click="run('move_section', { section_id: section.id, direction: 'down' })"
                >
                  ↓
                </button></template
              >
            </div>
            <div
              v-for="placement in model.placements.filter((p) => p.section_id === section.id)"
              :key="placement.id"
              class="flex items-center gap-2 rounded border border-base-300 bg-base-100 mb-2 p-2"
              :class="selection.id === placement.id ? 'ring-1 ring-primary/60' : ''"
            >
              <button
                type="button"
                class="min-w-0 flex-1 text-left px-2 py-1"
                :data-editor-widget="placement.id"
                :disabled="pending"
                @click="choose('widget', placement.id)"
              >
                <span class="block truncate text-sm">{{ placement.title }}</span
                ><span class="block text-xs font-mono text-base-content/65">{{
                  placement.editable
                    ? placement.fields?.type.replaceAll("_", " ")
                    : "Library / unsupported definition"
                }}</span>
              </button>
              <button
                type="button"
                class="btn btn-xs btn-ghost"
                :data-editor-layout="placement.id"
                :aria-label="`Position ${placement.title}`"
                :disabled="pending"
                @click="choose('layout', placement.id)"
              >
                {{ placement.layout.w }} × {{ placement.layout.h }}
              </button>
            </div>
          </div>
          <p
            v-if="!model.placements.length"
            id="editor-empty"
            class="px-2 py-8 text-center text-sm text-base-content/65"
          >
            Start with a widget, or add sections to organize the dashboard.
          </p>
        </div>
      </section>
      <section
        class="min-w-0 rounded-lg border border-base-300 bg-base-200/30 self-start"
        aria-labelledby="editor-inspector-title"
      >
        <h2
          id="editor-inspector-title"
          class="border-b border-base-300 p-4 text-xs font-mono uppercase tracking-widest"
        >
          {{ inspectorTitle }}
        </h2>
        <form id="dashboard-editor-form" class="p-4" @submit.prevent="applyChanges">
          <fieldset class="space-y-4 min-w-0" :disabled="disabled">
            <template v-if="draft.kind === 'metadata'"
              ><label class="editor-field" for="editor-name"
                >Name<input
                  id="editor-name"
                  v-model="draft.name"
                  required
                  maxlength="512"
                  class="input input-bordered input-sm w-full" /></label
              ><label class="editor-field" for="editor-description"
                >Description<textarea
                  id="editor-description"
                  v-model="draft.description"
                  rows="3"
                  maxlength="4096"
                  class="textarea textarea-bordered w-full"
                /></label
            ></template>
            <RuntimeDefaultsFields
              v-else-if="draft.kind === 'runtime'"
              v-model="draft.defaults_json"
            />
            <template v-else-if="draft.kind === 'section'"
              ><label class="editor-field" for="editor-section-title"
                >Section title<input
                  id="editor-section-title"
                  v-model="draft.title"
                  required
                  maxlength="512"
                  class="input input-bordered input-sm w-full" /></label
              ><label class="editor-field" for="editor-section-description"
                >Description<textarea
                  id="editor-section-description"
                  v-model="draft.description"
                  rows="3"
                  maxlength="4096"
                  class="textarea textarea-bordered w-full"
                /></label
              ><label class="flex gap-2 items-center text-xs"
                ><input
                  id="editor-section-collapsed"
                  v-model="draft.collapsed_by_default"
                  type="checkbox"
                  class="checkbox checkbox-sm"
                />
                Collapsed by default</label
              ></template
            >
            <template v-else-if="draft.kind === 'layout'"
              ><p class="text-xs text-base-content/60">
                Grid coordinates are zero-based. The server applies the dashboard's column count and
                widget minimum sizes.
              </p>
              <div class="grid grid-cols-2 gap-3">
                <label
                  v-for="[key, label] in layoutFields"
                  :key="key"
                  class="editor-field"
                  :for="`editor-layout-${key}`"
                  >{{ label
                  }}<input
                    :id="`editor-layout-${key}`"
                    v-model.number="draft[key]"
                    type="number"
                    :min="['w', 'h'].includes(key) ? 1 : 0"
                    :max="key === 'x' ? 47 : key === 'w' ? 48 : key === 'h' ? 1024 : 100000"
                    required
                    class="input input-bordered input-sm w-full"
                /></label></div
            ></template>
            <template
              v-else-if="draft.kind === 'widget' && (!selection.id || selectedPlacement?.editable)"
              ><WidgetFields
                v-model="draft.fields"
                :sections="model.sections"
                @type-change="typeChanged"
              /><ObservablePicker
                v-if="!['event_timeline', 'constellation_health'].includes(draft.fields.type)"
                :key="selection.id || 'new-widget'"
                v-model="draft.observables"
                :fields="draft.fields"
                :context="context"
                :document-version="model.document_version"
                :staging-revision="state.revision"
                :port="port"
                :disabled="disabled"
              />
              <p v-else class="text-xs text-base-content/60">
                This widget uses its built-in event or fleet-health binding.
              </p></template
            >
            <p v-else id="editor-definition-readonly" class="text-sm text-base-content/65">
              This definition cannot be edited as an embedded widget. Its library pin remains
              intact; position and removal are available here.
            </p>
            <div class="flex flex-wrap gap-2 border-t border-base-300 pt-4">
              <button
                v-if="selection.kind !== 'widget' || !selection.id || selectedPlacement?.editable"
                id="editor-save"
                type="submit"
                class="btn btn-sm btn-primary"
                :disabled="!dirty"
              >
                Apply to candidate</button
              ><button
                id="editor-discard"
                type="button"
                class="btn btn-sm btn-ghost"
                :disabled="!dirty"
                @click="choose(selection.kind, selection.id)"
              >
                Discard field edits</button
              ><button
                v-if="selection.id"
                id="editor-remove"
                type="button"
                class="btn btn-sm btn-ghost text-error ml-auto"
                :disabled="dirty"
                @click="remove"
              >
                Remove {{ selection.kind === "section" ? "section" : "widget" }}
              </button>
            </div>
          </fieldset>
        </form>
      </section>
    </div>
    <details id="editor-preview" class="rounded-lg border border-base-300 bg-base-200/20">
      <summary class="cursor-pointer p-4 text-xs font-mono">
        CANDIDATE PREVIEW · r{{ state.revision }} · based on v{{ model.document_version }} ·
        document-default context
      </summary>
      <div class="border-t border-base-300 p-4">
        <WorkspaceSnapshotCanvas
          v-if="model.preview"
          :snapshot="model.preview"
          :context="context"
          :instance-id="instanceId"
        />
        <p v-else class="text-sm text-base-content/60">
          Preview is unavailable. The candidate remains available for editing; its changes are not
          saved automatically.
        </p>
      </div>
    </details>
  </main>
</template>
<style scoped>
.editor-layout {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(20rem, 28rem);
  gap: 1rem;
}
.editor-field {
  display: grid;
  gap: 0.375rem;
  font-size: 0.75rem;
  min-width: 0;
}
@media (max-width: 900px) {
  .editor-layout {
    grid-template-columns: minmax(0, 1fr);
  }
}
</style>
