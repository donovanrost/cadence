import { mount } from "@vue/test-utils";
import { computed } from "vue";
import { afterEach, beforeEach, describe, expect, it, vi } from "vite-plus/test";
import { decode, missionId } from "@/api/index.ts";
import { actionQueueReader, presentQueue } from "./actionQueue.ts";
import ActionQueuePanel from "./ActionQueuePanel.vue";
import { unshownWords } from "./unshown.ts";

vi.mock("@/shell/index.ts", async (original) => ({
  ...(await original<typeof import("@/shell/index.ts")>()),
  useMissionScope: () => computed(() => ({ mission: { id: missionId("m-1"), name: "EARENDIL" } })),
}));
vi.mock("@/features/commands/index.ts", async (original) => ({
  ...(await original<typeof import("@/features/commands/index.ts")>()),
  useCommandAccess: () => computed(() => ({ abort: true, approve: false })),
}));

const NOW = new Date("2026-11-17T13:00:00Z");
/** A command_failed item as api serves it: one row each. */
const failed = (id: string, o: Record<string, unknown> = {}) => ({
  id,
  priority: 2,
  kind: "command_failed",
  state: "caution",
  source: null,
  acknowledged: null,
  since: "2026-11-17T12:00:00Z",
  count: 1,
  spacecraft: [],
  point: null,
  condition: null,
  plane: null,
  command: { id: `cmd-${id}`, name: "SET_MODE" },
  outcome: "failed",
  command_requests: [],
  finding: null,
  ...o,
});
/** One the console can't read: a contact_start attention missing its fields. */
const broken = (id: string) =>
  failed(id, {
    kind: "attention",
    attention: { id: `a-${id}`, source: "contact_start", raised_at: "SECRET-PAYLOAD" },
  });
const queueOf = (items: unknown[], resolved?: unknown[]) => {
  const r = decode(actionQueueReader, {
    observed_at: NOW.toISOString(),
    counts: { p1: 0, p2: items.length, p3: 0, spacecraft_p1: 0 },
    items,
    ...(resolved ? { resolved } : {}),
  });
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
};
const panel = (items: unknown[]) => {
  const q = queueOf(items);
  return mount(ActionQueuePanel, {
    props: {
      state: { status: "ready", value: presentQueue(q, NOW), receivedAt: NOW },
      nominal: 12,
      unshown: q.unshown,
    },
    global: { stubs: { RouterLink: { template: "<a><slot /></a>" } } },
  });
};

beforeEach(() => {
  vi.spyOn(console, "warn").mockImplementation(() => {});
});
afterEach(() => vi.restoreAllMocks());

/** U86: one item Now can't read no longer fails the whole queue. */
describe("Now's queue, read item by item (ux U86)", () => {
  it("drops the bad item, keeps the rest, and names it by kind, source and id", () => {
    const warn = vi.spyOn(console, "warn");
    const q = queueOf([failed("i-1"), broken("i-2"), failed("i-3")]);
    expect(q.items.map((i) => i.id)).toEqual(["i-1", "i-3"]);
    expect(q.unshown).toEqual([{ kind: ["attention", "contact_start"], id: "i-2" }]);
    expect(presentQueue(q, NOW)).toHaveLength(2);
    const said = warn.mock.calls.map((c) => String(c[0])).join("\n");
    expect(said).toContain("Now's queue: an item isn't shown (attention, contact_start, i-2)");
    expect(said).not.toContain("SECRET-PAYLOAD");
  });

  it("a kind this console doesn't know is left out and counted (#71)", () => {
    const q = queueOf([failed("i-1"), failed("i-2", { kind: "brand_new" })]);
    expect(q.items.map((i) => i.id)).toEqual(["i-1"]);
    expect(q.unshown).toEqual([{ kind: ["brand_new"], id: "i-2" }]);
  });

  it("an unreadable resolved entry doesn't fail the queue either", () => {
    const q = queueOf([failed("i-1")], [{ id: "x", source: "contact_start" }]);
    expect(q.items).toHaveLength(1);
    expect(q.resolved).toEqual([]);
    expect(q.unshown).toEqual([]);
  });

  it("6 open over 5 rows plus the line for 1, at the top (header total includes it)", () => {
    const w = panel([
      broken("i-0"),
      ...["i-1", "i-2", "i-3", "i-4", "i-5"].map((id) => failed(id)),
    ]);
    expect(w.text()).toContain("6 open · sorted by urgency");
    expect(w.findAll("ul > li")).toHaveLength(5);
    const line = w.find('[role="status"]');
    expect(line.text()).toContain(unshownWords(1));
    expect(line.find("summary").text()).toBe("Technical details");
    expect(line.find("details p").text()).toBe("attention, contact_start, i-0");
    expect(line.find("button").text()).toBe("Reload");
    expect(w.html().indexOf(unshownWords(1))).toBeLessThan(w.html().indexOf("<ul"));
  });

  it("all dropped: the line alone, never 'Nothing needs you'", () => {
    const w = panel([broken("i-1"), broken("i-2")]);
    expect(w.text()).toContain("2 open · sorted by urgency");
    expect(w.text()).toContain(
      "This console can't show 2 items. Reload to try again. If they're still missing, tell the team that runs Cadence for you.",
    );
    expect(w.text()).not.toContain("Nothing needs you");
    expect(
      w
        .find('[role="status"]')
        .findAll("details p")
        .map((p) => p.text()),
    ).toEqual(["attention, contact_start, i-1", "attention, contact_start, i-2"]);
  });

  it("nothing dropped: no line", () => {
    const w = panel([failed("i-1")]);
    expect(w.text()).toContain("1 open · sorted by urgency");
    expect(w.text()).not.toContain("can't show");
    expect(panel([]).text()).toContain("Nothing needs you");
  });

  it("words one item as ux has it", () => {
    expect(unshownWords(1)).toBe(
      "This console can't show 1 item. Reload to try again. If it's still missing, tell the team that runs Cadence for you.",
    );
  });
});
