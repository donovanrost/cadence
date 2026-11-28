import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId as missionIdReader } from "@/api/index.ts";
import ActivationDecide from "./ActivationDecide.vue";
import ChangesPanel from "./ChangesPanel.vue";
import type { ActivationDetail } from "./api.ts";
import { APPROVE_UNSHOWN } from "./changesWords.ts";
import { configurationChangesReader } from "./configurationChanges.ts";

const requestKey = { missionId: missionIdReader("m-1"), requestId: "act_1" };
const stubs = { RouterLink: { template: "<a><slot /></a>" } };
const craft = (n: number) => ({ spacecraft_id: `sc_${n}`, name: `EARENDIL-${n}` });
const catalogRow = {
  field: "catalog_revision",
  label: "Catalog revision",
  before: { id: "cr_13", number: 13 },
  after: { id: "cr_14", number: 14 },
};
const fleet = (rows: readonly unknown[]) =>
  configurationChangesReader({
    groups: [
      {
        rows,
        first_start: false,
        telemetry_enabled: false,
        count: 5,
        spacecraft: [1, 2, 3, 4, 5].map(craft),
      },
      { rows: [], first_start: false, telemetry_enabled: true, count: 1, spacecraft: [craft(9)] },
    ],
    total: 6,
  });

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe("#235 What changes panel", () => {
  it("shows the summary, the crit line, each group, and pages names in from Show all", async () => {
    const fetch = vi.fn<(url: string) => Promise<Response>>();
    fetch.mockResolvedValueOnce(
      new Response(
        JSON.stringify({ data: { spacecraft: [1, 2, 3, 4, 5].map(craft), next_offset: null } }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );
    vi.stubGlobal("fetch", fetch);
    const w = mount(ChangesPanel, {
      props: { changes: fleet([catalogRow]), requestKey, index: "R2" },
      global: { stubs },
    });
    const text = w.text();
    expect(text).toContain("What changes · 6 spacecraft");
    expect(text).toContain("5 spacecraft change: Catalog revision (5).");
    expect(text).toContain("1 has no changes.");
    expect(text).toContain("Telemetry is off for 5 of the 6 spacecraft");
    expect(text).toContain("Open spacecraft");
    expect(text).toContain("EARENDIL-1, EARENDIL-2, EARENDIL-3 and 2 more");
    expect(text).toContain("Catalog revision: catalog rev 13 → catalog rev 14");
    expect(text).toContain("No changes on 1 spacecraft: EARENDIL-9.");
    const names = () => w.findAll("li").map((li) => li.text());
    const toggle = () =>
      w.findAll("button").find((b) => /^(Show names \(5\)|Hide names)$/.test(b.text()));
    expect(toggle()?.text()).toBe("Show names (5)");
    await toggle()?.trigger("click");
    await flushPromises();
    expect(fetch.mock.calls[0]?.[0]).toContain(
      "/activations/act_1/configuration-changes?group=0&offset=0",
    );
    // #176: a real list, one name per item, not a comma paragraph.
    expect(names()).toEqual(expect.arrayContaining(["EARENDIL-1", "EARENDIL-4", "EARENDIL-5"]));
    // #244 (B3, A5): a disclosure that stays mounted, so focus isn't dropped.
    expect(toggle()?.text()).toBe("Hide names");
    expect(toggle()?.attributes("aria-expanded")).toBe("true");
    await toggle()?.trigger("click");
    expect(toggle()?.text()).toBe("Show names (5)");
    expect(toggle()?.attributes("aria-expanded")).toBe("false");
    expect(names()).not.toContain("EARENDIL-4");
    // Closing keeps what's loaded: opening again reads nothing.
    await toggle()?.trigger("click");
    await flushPromises();
    expect(names()).toContain("EARENDIL-4");
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("pages a big group's names: Showing 100 of 250, then Load more by offset (#176)", async () => {
    const page = (from: number, to: number, next: number | null) =>
      new Response(
        JSON.stringify({
          data: {
            spacecraft: Array.from({ length: to - from }, (_, i) => craft(from + i)),
            next_offset: next,
          },
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    const fetch = vi.fn<(url: string) => Promise<Response>>();
    fetch.mockResolvedValueOnce(page(0, 100, 100)).mockResolvedValueOnce(page(100, 200, 200));
    vi.stubGlobal("fetch", fetch);
    const big = configurationChangesReader({
      groups: [
        {
          rows: [catalogRow],
          first_start: false,
          telemetry_enabled: true,
          count: 250,
          spacecraft: [1, 2, 3].map(craft),
        },
      ],
      total: 250,
    });
    const w = mount(ChangesPanel, {
      props: { changes: big, requestKey, index: "R2" },
      global: { stubs },
    });
    await w
      .findAll("button")
      .find((b) => b.text() === "Show names (250)")
      ?.trigger("click");
    await flushPromises();
    expect(w.findAll("li").filter((li) => li.text().startsWith("EARENDIL-"))).toHaveLength(100);
    expect(w.text()).toContain("Showing 100 of 250");
    await w
      .findAll("button")
      .find((b) => b.text() === "Load more")
      ?.trigger("click");
    await flushPromises();
    expect(fetch.mock.calls[1]?.[0]).toContain("group=0&offset=100");
    expect(w.text()).toContain("Showing 200 of 250");
  });

  it("keeps Approve off while a change can't be shown, and Reject on", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const changes = fleet([catalogRow, { field: "new_field", label: "New", before: 1, after: 2 }]);
    const panel = mount(ChangesPanel, {
      props: { changes, requestKey, index: "R2" },
      global: { stubs },
    });
    expect(panel.text()).toContain("This console can't show 1 change.");
    const request: ActivationDetail = {
      id: "act_1",
      kind: "spacecraft_configuration",
      summary: "Spacecraft configuration for 6 spacecraft",
      binding_set: { id: "bs_1", version: 4 },
      requested_by: { kind: "user", id: "u1", name: "Mira K." },
      requested_at: "2026-11-18T02:10:00Z",
      state: "approval_pending",
      decision: null,
      execution: null,
      can_decide: true,
      superseded_by: undefined,
      superseded_at: undefined,
      details: [],
      comparison: null,
      permissions: undefined,
      configuration_changes: changes,
    };
    const w = mount(ActivationDecide, {
      props: { requestKey, request, viewer: { userId: "u2" }, index: "R3" },
      global: { stubs },
    });
    await w.find("textarea").setValue("Looks right.");
    const approve = w.findAll("button").find((b) => b.text().startsWith("Approve and apply"));
    expect(approve?.attributes("aria-disabled")).toBe("true");
    expect(approve?.attributes("title")).toBe(APPROVE_UNSHOWN);
    const reject = w.findAll("button").find((b) => b.text().startsWith("Reject"));
    expect(reject?.attributes("aria-disabled")).toBeUndefined();
  });
});
