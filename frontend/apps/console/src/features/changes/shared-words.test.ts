import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { previewReader } from "./actions.ts";
import { opFields, opHead, type ChangeOp } from "./change-ops-words.ts";
import EntryList from "./EntryList.vue";
import { conflictSentences } from "./itemLines.ts";
import RevisionsTable from "./RevisionsTable.vue";
import { entry, revisionSummary } from "./shapes.ts";

/** #308 part 2: mms-ux's table, the Changes rows (✕, shared with C&A; ca-ux agreed). */
const op = (o: Partial<ChangeOp>): ChangeOp => ({
  id: "op-1",
  kind: "transport",
  entity_id: "t-1",
  action: "update",
  paths: [],
  payload: null,
  ...o,
});
const schema = {
  fields: [
    { path: "name", label: "Name" },
    { path: "frame_size", label: "Frame size" },
  ],
};

describe("ChangeOps words (d): verbs and field labels, never raw ops", () => {
  it("reads the act and the kind, and the fields by label with the rest counted", () => {
    expect(opHead(op({}))).toBe("Changed transport");
    expect(opHead(op({ kind: "spacecraft_route", action: "create" }))).toBe("Added extra route");
    expect(opFields(op({ paths: ["name", "frame_size", "a.b", "c"] }), schema)).toBe(
      "Name, Frame size and 2 other settings",
    );
    expect(opFields(op({ paths: ["name"] }), schema)).toBe("Name");
    expect(opFields(op({ paths: ["a.b", "c"] }), null)).toBe("2 settings");
    expect(opFields(op({ paths: [] }), schema)).toBeNull();
  });
});

describe("a conflict's subject (b): the name, else 'Unknown <kind>', never an id", () => {
  it("words a nameless entity", () => {
    const r = decode(previewReader, {
      verdict: "hold",
      checks: [
        {
          key: "conflicts",
          verdict: "hold",
          items: [
            {
              kind: "spacecraft_profile",
              entity_id: "sp-9",
              paths: [
                {
                  path: "catalog_revision_id",
                  label: "Catalog revision",
                  base: 2,
                  live: 3,
                  staged: 4,
                  changed_in: "outside",
                },
              ],
            },
          ],
        },
      ],
      effects: [],
    });
    if (!r.ok) throw new Error(JSON.stringify(r.error));
    const item = r.value.checks[0]?.items[0];
    if (!item) throw new Error("no item");
    const line = conflictSentences(item) ?? "";
    expect(line).toMatch(/^Unknown profile · Catalog revision is 3 now/);
    expect(line).not.toContain("sp-9");
  });
});

describe("Revisions and change lists (a, b, c)", () => {
  const nameless = { kind: "user", id: "u9", name: null };
  const row = (o: Record<string, unknown>) =>
    revisionSummary({
      revision: 7,
      kind: "change_set",
      live: false,
      applied_at: "2026-11-17T09:12:00Z",
      applied_by: nameless,
      reason: null,
      summary: null,
      entry_count: 1,
      change_set_id: "cs7",
      rolls_back_to: null,
      approvals: [],
      ...o,
    });

  it("a nameless person reads 'Not known'; counts read 'changes'; the older kind its words", () => {
    const w = mount(RevisionsTable, {
      props: {
        rows: [row({}), row({ revision: 6, kind: "legacy_activation", entry_count: 3 })],
        selected: [],
      },
      global: { stubs: { RouterLink: true } },
    });
    expect(w.text()).toContain("Not known");
    expect(w.text()).not.toContain("someone");
    expect(w.text()).toContain("1 change");
    expect(w.text()).toContain("3 changes");
    expect(w.text()).toContain("Activated outside change sets");
  });

  it("a change entry with no name shows the act and kind only, and the meta counts changes", () => {
    const r = decode(entry, {
      revision: 7,
      kind: "spacecraft_profile",
      entity_id: "sp-9",
      entity_name: null,
      op: "update",
      paths: [],
      fields: [],
    });
    if (!r.ok) throw new Error(JSON.stringify(r.error));
    const w = mount(EntryList, { props: { entries: [r.value] } });
    expect(w.text()).toContain("Changed profile");
    expect(w.text()).toContain("1 change");
    expect(w.text()).not.toContain("sp-9");
  });
});
