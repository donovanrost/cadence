import { mount } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, it, vi } from "vite-plus/test";
import { decode } from "@/api";
import { auditReader } from "./api.ts";
import AuditResults from "./AuditResults.vue";
import { unreadNote } from "./export.ts";

const ok = (id: string) => ({
  id,
  at: "2026-11-10T05:00:00Z",
  actor: null,
  kind: "config",
  action: "Applied r6 · 2 changes",
  target: null,
  mission: null,
  reason: null,
});
/** One this console can't read: its target has no label (P3's constraint broken). */
const bad = (id: string) => ({
  ...ok(id),
  kind: "activations",
  target: { kind: "x", id: "1", label: null },
});
const page = (events: unknown[]) => {
  const r = decode(auditReader, {
    events,
    sources: { included: ["config"], missing: [] },
    next_cursor: null,
  });
  if (!r.ok) throw r.error;
  return r.value;
};
const results = (events: unknown[]) =>
  mount(AuditResults, {
    props: {
      page: page(events),
      older: [],
      olderUnshown: [],
      hasMore: false,
      loading: false,
      failed: false,
      span: "7 days",
    },
    global: {
      stubs: { AuditTable: { props: ["events"], template: "<table :data-n='events.length' />" } },
    },
  });

beforeEach(() => vi.spyOn(console, "warn").mockImplementation(() => {}));
afterEach(() => vi.restoreAllMocks());

/** ux U86 follow-up: one Org Audit event the console can't read no longer blanks the log. */
describe("Org Audit, read event by event (U86)", () => {
  it("keeps the readable events and counts the rest by kind and id", () => {
    const p = page([ok("e1"), bad("e2"), ok("e3")]);
    expect(p.events.map((e) => e.id)).toEqual(["e1", "e3"]);
    expect(p.unshown).toEqual([{ kind: ["activations"], id: "e2" }]);
  });

  it("the line sits above the table and names events", () => {
    const w = results([ok("e1"), bad("e2")]);
    expect(w.text()).toContain("This console can't show 1 event. Reload to try again.");
    expect(w.find("table").attributes("data-n")).toBe("1");
    expect(w.html().indexOf("can't show")).toBeLessThan(w.html().indexOf("<table"));
  });

  it("all dropped: the line alone, never 'No audited actions'", () => {
    const w = results([bad("e1"), bad("e2")]);
    expect(w.text()).toContain("This console can't show 2 events.");
    expect(w.text()).not.toContain("No audited actions");
    expect(w.find("table").exists()).toBe(false);
  });

  it("the export never ships a silent short file", () => {
    expect(unreadNote(1)).toBe("1 event couldn't be read, so it isn't in this file.");
    expect(unreadNote(3)).toBe("3 events couldn't be read, so they aren't in this file.");
  });
});
