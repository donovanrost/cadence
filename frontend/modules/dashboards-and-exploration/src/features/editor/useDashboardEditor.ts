import { computed, nextTick, reactive, ref, shallowRef, watch } from "vue";
import type { OpsPageContext, OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import type { EditorAction, EditorState } from "./contracts";
import { readEditor, record } from "./validation";
import { formatRuntimeDefaults, parseRuntimeDefaults } from "./runtime-defaults";

export type EditorProps = {
  state: EditorState;
  context: OpsPageContext;
  port: OpsPagePort;
  refresh: () => Promise<void>;
};
type Selection = {
  kind: "metadata" | "runtime" | "section" | "widget" | "layout" | "arrange";
  id?: string;
};
export function useDashboardEditor(props: EditorProps) {
  const state = shallowRef(props.state),
    selection = ref<Selection>({ kind: "metadata" });
  const draft = reactive<Record<string, any>>({}),
    baseline = ref("");
  const pending = ref(false),
    gesturing = ref(false),
    locked = ref(props.state.phase === "review"),
    notice = ref("");
  let sequence = props.state.sequence,
    disposed = false;
  const dirty = computed(() => JSON.stringify(draft) !== baseline.value);
  const unsaved = computed(() => dirty.value || state.value.dirty);
  const selectedPlacement = computed(() =>
    state.value.model.placements.find((p) => p.id === selection.value.id),
  );
  function reset() {
    const model = state.value.model,
      selected = selection.value;
    let value: Record<string, any>;
    if (selected.kind === "arrange") value = { layouts: [] };
    else if (selected.kind === "runtime")
      value = {
        defaults_json: formatRuntimeDefaults(parseRuntimeDefaults(model.runtime_defaults_json)),
      };
    else if (selected.kind === "metadata")
      value = { name: model.name, description: model.description };
    else if (selected.kind === "section") {
      const section = model.sections.find((s) => s.id === selected.id);
      value = section
        ? {
            title: section.title,
            description: section.description,
            collapsed_by_default: section.collapsed_by_default,
          }
        : { title: "", description: "", collapsed_by_default: false };
    } else if (selected.kind === "layout") {
      const layout = selectedPlacement.value?.layout;
      value = { x: layout?.x ?? 0, y: layout?.y ?? 0, w: layout?.w ?? 4, h: layout?.h ?? 3 };
    } else {
      const placement = selectedPlacement.value;
      value = {
        fields: { ...(placement?.fields ?? model.defaults) },
        observables: placement?.observables.join("\n") ?? "",
      };
    }
    for (const key of Object.keys(draft)) delete draft[key];
    Object.assign(draft, value);
    baseline.value = JSON.stringify(draft);
  }
  reset();
  watch(
    () => props.state,
    (next) => {
      if (pending.value || disposed) return;
      sequence = next.sequence;
      if (
        (dirty.value || gesturing.value) &&
        (next.model.document_version !== state.value.model.document_version ||
          next.revision !== state.value.revision)
      ) {
        locked.value = true;
        notice.value = "The saved draft changed. Reload and review it before editing again.";
        return;
      }
      state.value = next;
      if (next.phase === "review") locked.value = true;
      if (!dirty.value) reset();
    },
  );
  function canLeave() {
    return (
      !pending.value &&
      !gesturing.value &&
      (!unsaved.value || window.confirm("Discard unsaved dashboard edits?"))
    );
  }
  function choose(kind: Selection["kind"], id?: string) {
    if (
      disposed ||
      pending.value ||
      gesturing.value ||
      (dirty.value && !window.confirm("Discard unapplied field edits?"))
    )
      return;
    selection.value = { kind, id };
    reset();
    notice.value = "";
  }
  async function run(action: EditorAction, payload: Record<string, unknown> = {}) {
    if (
      disposed ||
      pending.value ||
      gesturing.value ||
      (locked.value && action !== "reload_editor")
    )
      return false;
    pending.value = true;
    notice.value = "";
    const requested = ++sequence,
      version = state.value.model.document_version,
      revision = state.value.revision,
      stagedDirty = state.value.dirty;
    try {
      const response = record(
        await props.port.execute(action, {
          sequence: requested,
          command:
            action === "reload_editor"
              ? {}
              : { ...payload, expected_version: version, expected_revision: revision },
        }),
      );
      if (disposed) return false;
      const next = readEditor(response.state, props.context);
      if (next.sequence !== requested) throw Error("Unconfirmed sequence");
      if (
        response.status === "invalid" &&
        next.phase === "editing" &&
        next.model.document_version === version &&
        next.revision === revision &&
        next.dirty === stagedDirty
      ) {
        const errors: Record<string, string> = {
          invalid_input: "Check the field values and observable IDs.",
          invalid_defaults:
            "Check runtime defaults: use a bounded JSON object with supported time, scope, data and limit contexts.",
          invalid_title: "Enter a widget title of 1–120 characters.",
          invalid_options: "Check the widget's display options and numeric ranges.",
          invalid_binding: "The selected observables do not support this source or scope.",
          invalid_widget: "Check the observable count and source for this widget type.",
          invalid_document:
            "The dashboard is not ready for this operation. Check its bindings and source capabilities.",
          missing_section: "The selected section is unavailable.",
          missing_placement: "The selected widget is unavailable.",
          unsupported_widget: "Edit this definition in its owning library or supported editor.",
          invalid_type: "Choose a supported widget type.",
          capacity: "The dashboard has reached its section or widget limit.",
        };
        if (typeof response.code !== "string" || !Object.hasOwn(errors, response.code))
          throw Error("Unknown error");
        state.value = next;
        notice.value = errors[response.code];
        return false;
      }
      if (response.status !== "ok" || next.phase !== "editing") throw Error("Unconfirmed write");
      const expected = action === "save_draft" && stagedDirty ? version + 1 : version;
      if (next.revision !== (action === "reload_editor" ? 0 : revision + 1))
        throw Error("Unconfirmed staging revision");
      if (["save_draft", "discard_draft", "reload_editor"].includes(action) && next.dirty)
        throw Error("Unconfirmed clean draft");
      if (action !== "reload_editor" && next.model.document_version !== expected)
        throw Error("Unconfirmed version");
      if (action === "reload_editor" && next.model.document_version < version)
        throw Error("Older draft");
      state.value = next;
      locked.value = false;
      if (["remove_section", "remove_widget", "reload_editor", "discard_draft"].includes(action))
        selection.value = { kind: "metadata" };
      if (action === "add_section" || action === "add_widget")
        selection.value = { kind: "metadata" };
      reset();
      notice.value =
        action === "save_draft"
          ? `Draft version ${next.model.document_version} saved.`
          : action === "discard_draft"
            ? "Staged changes discarded. The starting draft is unchanged."
            : action === "reload_editor"
              ? "Saved draft reloaded. Review it before continuing."
              : "Changes staged. Save draft to persist them.";
      return true;
    } catch {
      if (!disposed) {
        locked.value = true;
        notice.value =
          "The operation could not be confirmed, or the draft changed. Reload the saved draft before continuing; do not repeat the operation blindly.";
      }
      return false;
    } finally {
      if (!disposed) pending.value = false;
    }
  }
  function applyChanges() {
    const s = selection.value;
    if (s.kind === "runtime") {
      try {
        parseRuntimeDefaults(draft.defaults_json);
      } catch (error) {
        notice.value = error instanceof Error ? error.message : "Check runtime defaults.";
        return false;
      }
      return run("runtime_defaults", { defaults_json: draft.defaults_json });
    }
    if (s.kind === "arrange") return run("layout", { layouts: draft.layouts });
    if (s.kind === "metadata") return run("rename", { ...draft });
    if (s.kind === "section")
      return run(s.id ? "update_section" : "add_section", {
        ...draft,
        ...(s.id ? { section_id: s.id } : {}),
      });
    if (s.kind === "layout") return run("layout", { layouts: [{ ...draft, placement_id: s.id }] });
    return run(s.id ? "update_widget" : "add_widget", {
      fields: { ...draft.fields },
      observables: draft.observables
        .split(/[\n,]/)
        .map((s: string) => s.trim())
        .filter(Boolean),
      ...(s.id ? { placement_id: s.id } : {}),
    });
  }
  async function saveDraft() {
    if (disposed || pending.value || gesturing.value || locked.value) return false;
    if (dirty.value && !(await applyChanges())) return false;
    return run("save_draft");
  }
  async function discardDraft() {
    if (disposed || pending.value || gesturing.value || locked.value || !unsaved.value)
      return false;
    if (!window.confirm("Discard all unsaved dashboard changes?")) return false;
    return run("discard_draft");
  }
  async function review() {
    if (!(await saveDraft()) || disposed) return;
    const model = state.value.model;
    try {
      await props.port.navigate(
        `/missions/${encodeURIComponent(model.mission_id)}/ops/dashboards/${encodeURIComponent(model.dashboard_id)}/activity?version=${model.document_version}`,
      );
    } catch {
      if (!disposed)
        notice.value =
          "The draft is saved, but Activity could not be opened. You can retry Review & publish.";
    }
  }
  async function reload() {
    if (disposed || pending.value || !canLeave()) return;
    pending.value = true;
    try {
      await props.refresh();
      await nextTick();
      if (disposed) return;
      sequence = props.state.sequence;
    } catch {
      notice.value = "The saved draft could not be refreshed.";
      return;
    } finally {
      if (!disposed) pending.value = false;
    }
    return run("reload_editor");
  }
  return {
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
    canLeave,
    choose,
    applyChanges,
    saveDraft,
    discardDraft,
    review,
    run,
    reload,
    dispose: () => {
      disposed = true;
    },
  };
}
