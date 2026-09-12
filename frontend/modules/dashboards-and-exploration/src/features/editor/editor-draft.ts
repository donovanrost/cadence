import type { EditorModel, WidgetFields } from "./contracts";
import { formatRuntimeDefaults, parseRuntimeDefaults } from "./runtime-defaults";
import type { LayoutEdit } from "./layout-draft";
export type EditorDraft =
  | { kind: "metadata"; name: string; description: string }
  | { kind: "runtime"; defaults_json: string }
  | { kind: "section"; title: string; description: string; collapsed_by_default: boolean }
  | { kind: "layout"; x: number; y: number; w: number; h: number }
  | { kind: "arrange"; layouts: LayoutEdit[] }
  | { kind: "widget"; fields: WidgetFields; observables: string };
export type EditorSelection = { kind: EditorDraft["kind"]; id?: string };

/** Every panel gets its own mutable copy. Discriminants never enter native command payloads. */
export function editorDraft(model: EditorModel, selected: EditorSelection): EditorDraft {
  switch (selected.kind) {
    case "metadata":
      return { kind: selected.kind, name: model.name, description: model.description };
    case "runtime":
      return {
        kind: selected.kind,
        defaults_json: formatRuntimeDefaults(parseRuntimeDefaults(model.runtime_defaults_json)),
      };
    case "arrange":
      return { kind: selected.kind, layouts: [] };
    case "section": {
      const section = model.sections.find((section) => section.id === selected.id);
      return {
        kind: selected.kind,
        title: section?.title ?? "",
        description: section?.description ?? "",
        collapsed_by_default: section?.collapsed_by_default ?? false,
      };
    }
    case "layout": {
      const layout = model.placements.find((placement) => placement.id === selected.id)?.layout;
      return {
        kind: selected.kind,
        x: layout?.x ?? 0,
        y: layout?.y ?? 0,
        w: layout?.w ?? 4,
        h: layout?.h ?? 3,
      };
    }
    case "widget": {
      const placement = model.placements.find((placement) => placement.id === selected.id);
      return {
        kind: selected.kind,
        fields: { ...(placement?.fields ?? model.defaults) },
        observables: placement?.observables.join("\n") ?? "",
      };
    }
  }
}
type Payload<K extends EditorDraft["kind"]> = Omit<Extract<EditorDraft, { kind: K }>, "kind">;
type EditorInputs = {
  rename: Payload<"metadata">;
  runtime_defaults: Payload<"runtime">;
  add_section: Payload<"section">;
  update_section: Payload<"section"> & { section_id: string };
  remove_section: { section_id: string };
  move_section: { section_id: string; direction: "up" | "down" };
  add_widget: { fields: WidgetFields; observables: string[] };
  update_widget: { fields: WidgetFields; observables: string[]; placement_id: string };
  remove_widget: { placement_id: string };
  layout: { layouts: LayoutEdit[] };
};
export type EditorCommand =
  | {
      [A in keyof EditorInputs]: [action: A, payload: EditorInputs[A]];
    }[keyof EditorInputs]
  | [action: "save_draft" | "discard_draft" | "reload_editor", payload?: Record<string, never>];
