import { expect, test } from "vite-plus/test";
import { editorDraft, type EditorCommand, type EditorDraft } from "./editor-draft";
import { editorFixture } from "./fixtures.test-support";

test("widget field drafts are isolated from the reviewed source model", () => {
  const model = editorFixture().model;
  const draft = editorDraft(model, { kind: "widget" });
  if (draft.kind !== "widget") throw Error("Expected widget draft");
  draft.fields.title = "Local change";
  expect(model.defaults.title).not.toBe("Local change");
  expect(editorDraft(model, { kind: "metadata" })).toEqual({
    kind: "metadata",
    name: model.name,
    description: model.description,
  });
});
test("editor commands correlate each action with its own payload", () => {
  const valid: EditorCommand = ["remove_widget", { placement_id: "battery" }];
  // @ts-expect-error Section identity cannot be used for a widget removal.
  const wrongIdentity: EditorCommand = ["remove_widget", { section_id: "power" }];
  const incomplete: EditorCommand = [
    "layout",
    {
      // @ts-expect-error Incomplete layouts cannot become an editor command.
      layouts: [{ placement_id: "battery", x: 0, y: 0 }],
    },
  ];
  const runtime: EditorDraft = { kind: "runtime", defaults_json: "{}" };
  // @ts-expect-error Runtime drafts have no widget fields.
  void runtime.fields;
  expect(valid[0]).toBe("remove_widget");
  void wrongIdentity;
  void incomplete;
});
