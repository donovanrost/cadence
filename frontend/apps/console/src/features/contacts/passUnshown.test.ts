import { mount } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, it, vi } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import PassResolutionsCallout from "@/features/scheduling/PassResolutionsCallout.vue";
import type { Pass } from "./api.ts";
import { passesPageReader } from "./passes-api.ts";
import { passAttentions, passAttentionTag, passUnshown } from "./passAttention.ts";

/** An open item as the pass carries it (the queue's object). */
const item = (id: string, o: Record<string, unknown> = {}) => ({
  id,
  source: "pass_resolution",
  conflict: null,
  state: "open",
  acknowledged_by: null,
  contact_id: null,
  station: null,
  provider: null,
  starts_at: null,
  raised_at: "2026-11-17T12:00:00Z",
  provider_message: null,
  resolution: null,
  ...o,
});
/** One this console can't read: its state isn't a string. */
const broken = (id: string) => item(id, { source: "contact_start", state: 42 });
const pass = (id: string, o: Record<string, unknown> = {}) => ({
  id,
  kind: "contact",
  state: "confirmed",
  pass_phase: "scheduled",
  delivery_state: "pending",
  spacecraft_id: "spacecraft-earendil-003",
  spacecraft: { id: "spacecraft-earendil-003", name: "EARENDIL-003", scid: 3 },
  station: { ref: "brs", id: null, code: "BRS", name: "Brisbane" },
  antenna: null,
  starts_at: "2026-11-17T14:00:00Z",
  ends_at: "2026-11-17T14:10:00Z",
  uplink_capable: true,
  source: { provider: "p-1", provider_name: "Northlight", synthetic: false },
  max_elevation_deg: null,
  plan: null,
  attention: null,
  ...o,
});
const passesOf = (...passes: unknown[]): readonly Pass[] => {
  const r = decode(passesPageReader, {
    from: "2026-11-17T00:00:00Z",
    to: "2026-11-18T00:00:00Z",
    counts: { total: 0, booked: 0, hand_started: 0, in_contact: 0, upcoming: 0, synthetic: 0 },
    passes,
  });
  if (!r.ok) throw new Error(r.error.message);
  return r.value.passes;
};

beforeEach(() => vi.spyOn(console, "warn").mockImplementation(() => {}));
afterEach(() => vi.restoreAllMocks());

/** U86: one item a pass carries that the console can't read no longer fails every pass. */
describe("a pass's attention items, read item by item (ux U86)", () => {
  it("attentions: keeps the readable ones; the rest are counted by source and id", () => {
    const [p] = passesOf(
      pass("pass-1", { attention: item("a-1"), attentions: [item("a-1"), broken("a-2")] }),
      pass("pass-2"),
    );
    if (!p) throw new Error("no pass");
    expect(passAttentions(p).map((a) => a.id)).toEqual(["a-1"]);
    expect(passUnshown(p)).toEqual([{ kind: ["contact_start"], id: "a-2" }]);
    // The tag's count is a total: the dropped item is still open.
    expect(passAttentionTag(p)).toEqual({ state: "caution", label: "Needs attention", more: 1 });
  });

  it("attention alone (no attentions yet): an unreadable top item reads null and is counted", () => {
    const [p] = passesOf(pass("pass-1", { attention: broken("a-9") }));
    if (!p) throw new Error("no pass");
    expect(p.attention).toBeNull();
    expect(passUnshown(p)).toEqual([{ kind: ["contact_start"], id: "a-9" }]);
    expect(passAttentionTag(p)).toEqual({ state: "caution", label: "Needs attention", more: 0 });
  });

  it("nothing dropped: nothing unshown, no extra keys", () => {
    const [p] = passesOf(pass("pass-1", { attention: item("a-1"), attentions: [item("a-1")] }));
    if (!p) throw new Error("no pass");
    expect(passUnshown(p)).toEqual([]);
    expect("attention_unshown" in p || "attentions_unshown" in p).toBe(false);
  });
});

describe("the pass resolutions callout (ux U86)", () => {
  const mountCallout = (passes: readonly Pass[]) =>
    mount(PassResolutionsCallout, {
      props: { passes: passes.filter((p) => p.attention || p.attention_unshown) },
      global: { stubs: { RouterLink: { template: "<a><slot /></a>" } } },
    });

  it("counts the dropped item in its total and lists it in its own line, above", () => {
    const w = mountCallout(
      passesOf(
        pass("pass-1", { attention: item("a-1") }),
        pass("pass-2", { attention: broken("a-2") }),
      ),
    );
    expect(w.text()).toContain("2 pass resolutions need you");
    expect(w.findAll("a")).toHaveLength(1);
    const html = w.html();
    expect(html.indexOf("This console can't show 1 item.")).toBeLessThan(
      html.indexOf("2 pass resolutions"),
    );
    expect(w.find("details p").text()).toBe("contact_start, a-2");
  });

  it("all dropped: the line shows, with the total", () => {
    const w = mountCallout(passesOf(pass("pass-2", { attention: broken("a-2") })));
    expect(w.text()).toContain("This console can't show 1 item.");
    expect(w.text()).toContain("1 pass resolution needs you");
    expect(w.findAll("a")).toHaveLength(0);
  });
});
