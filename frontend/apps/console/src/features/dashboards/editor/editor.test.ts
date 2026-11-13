import { afterEach, describe, expect, it } from "vite-plus/test";
import { commandReader, widgetDefaults, type Command } from "./contracts.ts";
import { editFailure } from "./api.ts";
import {
  MAX_COMMANDS,
  append,
  clearDraft,
  loadDraft,
  newId,
  storeDraft,
  type Draft,
} from "./draft.ts";

const layout = (id: string, x: number): Command => ({
  event: "layout",
  input: { layouts: [{ placement_id: id, x, y: 0, w: 4, h: 2 }] },
});
const update = (id: string, title: string): Command => ({
  event: "update_widget",
  input: { placement_id: id, fields: { ...widgetDefaults, title }, observables: [] },
});
const empty: Draft = { baseVersion: 3, commands: [] };
const appended = (draft: Draft, c: Command) => {
  const r = append(draft, c);
  if (!r.ok) throw new Error("append refused");
  return r.draft;
};

describe("draft", () => {
  it("collapses consecutive layout edits, last position winning per widget", () => {
    let d = appended(empty, layout("a", 0));
    d = appended(d, layout("b", 4));
    d = appended(d, layout("a", 8));
    expect(d.commands).toHaveLength(1);
    expect(d.commands[0]).toEqual({
      event: "layout",
      input: {
        layouts: [
          { placement_id: "a", x: 8, y: 0, w: 4, h: 2 },
          { placement_id: "b", x: 4, y: 0, w: 4, h: 2 },
        ],
      },
    });
  });

  it("keeps a layout edit separate once another edit comes between", () => {
    let d = appended(empty, layout("a", 0));
    d = appended(d, update("a", "Bus"));
    d = appended(d, layout("a", 4));
    expect(d.commands.map((c) => c.event)).toEqual(["layout", "update_widget", "layout"]);
  });

  it("collapses repeated updates of the same widget", () => {
    let d = appended(empty, update("a", "One"));
    d = appended(d, update("a", "Two"));
    d = appended(d, update("b", "Three"));
    expect(d.commands).toHaveLength(2);
  });

  it("refuses the edit after the server's cap instead of dropping any", () => {
    let d: Draft = empty;
    for (let i = 0; i < MAX_COMMANDS; i++) d = appended(d, update(`w${i}`, "x"));
    expect(append(d, update("one-more", "x"))).toEqual({ ok: false, reason: "too_many_commands" });
  });

  it("names new widgets with stable client ids", () => {
    expect(newId("dash_widget")).toMatch(/^dash_widget_[0-9a-f]{32}$/);
  });
});

describe("draft autosave", () => {
  afterEach(() => localStorage.clear());

  it("round-trips through storage and clears when empty", () => {
    storeDraft("m", "d", appended(empty, update("a", "Bus")));
    expect(loadDraft("m", "d")?.commands).toHaveLength(1);
    clearDraft("m", "d");
    expect(loadDraft("m", "d")).toBeNull();
  });

  it("ignores a stored draft it can't read", () => {
    localStorage.setItem(
      "cadence.console.dashboard-draft.m.d",
      '{"version":1,"commands":[{"event":"nope"}]}',
    );
    expect(loadDraft("m", "d")).toBeNull();
  });
});

describe("edit failures", () => {
  const draft = appended(empty, update("a", "Bus"));

  it("reads a version conflict with who saved", () => {
    const f = editFailure(
      {
        kind: "conflict",
        code: "version_conflict",
        message: "",
        details: {
          current_version: 5,
          saved_by: { kind: "user", id: "u", name: "Mira K." },
          saved_at: "2026-11-13T02:51:00Z",
        },
      },
      draft,
    );
    expect(f).toEqual({
      kind: "conflict",
      currentVersion: 5,
      savedBy: "Mira K.",
      savedAt: "2026-11-13T02:51:00Z",
    });
  });

  it("points a refused command at the draft's command", () => {
    const f = editFailure(
      {
        kind: "invalid",
        code: "invalid_command",
        message: "",
        details: { index: 0, code: "not_found", field: null },
      },
      draft,
    );
    expect(f.kind === "command" && f.command?.event).toBe("update_widget");
  });

  it("reads a library item retired before the save, which names no command (Q10)", () => {
    const f = editFailure(
      {
        kind: "invalid",
        code: "invalid_command",
        message: "",
        details: { index: null, code: "library_item_unavailable", field: "library_item_id" },
      },
      draft,
    );
    expect(f).toMatchObject({
      kind: "command",
      index: null,
      command: null,
      code: "library_item_unavailable",
      field: "library_item_id",
    });
  });

  it("keeps unknown failures generic", () => {
    expect(editFailure({ kind: "malformed", message: "x" }, draft).kind).toBe("other");
  });
});

describe("library placements (add_library_widget)", () => {
  it("round-trips through the command reader, as a stored draft replays it", () => {
    const command = {
      event: "add_library_widget",
      input: {
        placement_id: `dash_widget_${"a".repeat(32)}`,
        library_item_id: "lib-1",
        version: 3,
        section_id: "",
      },
    };
    expect(commandReader(command, "")).toEqual(command);
  });
});
