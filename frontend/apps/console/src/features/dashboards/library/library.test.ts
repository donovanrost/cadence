import { flushPromises, mount } from "@vue/test-utils";
import { missionId as missionIdReader } from "@/api/index.ts";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import {
  fetchLibrary,
  fetchLibraryItem,
  kindWord,
  retireItem,
  usedByOf,
  usedInWords,
} from "./api.ts";
import LibraryPicker from "./LibraryPicker.vue";

// No live socket in a unit test: invalidation is the shell's concern.
vi.mock("@/live", () => ({ useMissionInvalidation: () => undefined }));
import { previewOf } from "./preview.ts";

/** Fixtures in the D21/D22 proposal's shapes (plans/dashboards-library.md). */
const row = (id: string, over: Record<string, unknown> = {}) => ({
  id,
  name: `Battery tile ${id}`,
  description: null,
  kind: "cadence.value_tile",
  latest_version: 3,
  used_by_count: 2,
  updated_at: "2026-11-12T03:10:00Z",
  updated_by: { id: "u-1", name: "Ana P." },
  ...over,
});
const list = (items: unknown[]) => ({
  items,
  total: items.length,
  page: 1,
  pages: 1,
  page_size: 50,
  can_edit: true,
});
const detail = {
  item: {
    id: "lib-1",
    name: "Battery tile",
    description: "VBAT with limits",
    kind: "cadence.value_tile",
    latest_version: 3,
    updated_at: "2026-11-12T03:10:00Z",
    updated_by: { id: "u-1", name: "Ana P." },
  },
  version: {
    version: 3,
    definition_json:
      '{"widget_type_id":"cadence.value_tile","widget_type_version":1,"title":"VBAT","binding":{"observables":["EPS.VBAT"],"scope_mode":"context","sampling":"latest","aggregation":null},"options":{"precision":2}}',
    summary: "Two decimals",
    saved_at: "2026-11-12T03:10:00Z",
    saved_by: { id: "u-1", name: "Ana P." },
  },
  versions: [
    { version: 3, summary: "Two decimals", saved_at: "2026-11-12T03:10:00Z", saved_by: null },
  ],
  used_by: {
    dashboards: [{ id: "d-1", name: "Bus overview", placements: 2, pinned_versions: [] }],
  },
  can_edit: true,
};
const reply = (status: number, body: unknown) =>
  new Response(status === 204 ? null : JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
const stub = (...replies: Response[]) => {
  const fetch = vi.fn();
  for (const r of replies) fetch.mockResolvedValueOnce(r);
  vi.stubGlobal("fetch", fetch);
  return fetch;
};

describe("dashboards library (slice 8)", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("reads the list and an item; an unknown kind still reads", async () => {
    stub(
      // api ffd5c6d69: kind is the widget_type_id, namespaced; another vendor's keeps its id.
      reply(200, {
        data: list([
          row("a"),
          row("b", { kind: "cadence.sky_plot" }),
          row("c", { kind: "acme.gauge" }),
        ]),
      }),
      reply(200, { data: detail }),
    );
    const l = await fetchLibrary(missionIdReader("m"), { q: "", page: 1 });
    expect(l.ok && l.value.items.map((r) => kindWord(r.kind))).toEqual([
      "Value tile",
      "sky plot",
      "acme.gauge",
    ]);
    const item = await fetchLibraryItem(missionIdReader("m"), "lib-1", null);
    expect(item.ok && item.value.used_by.dashboards[0]?.name).toBe("Bus overview");
  });

  it("delete: 409 in use names the dashboards; 204 retires", async () => {
    const fetchMock = stub(
      reply(409, {
        error: {
          code: "library_item_in_use",
          message: "In use.",
          details: {
            used_by: {
              dashboards: [
                { id: "d-1", name: "Bus overview", placements: 1, pinned_versions: [2] },
                { id: "d-2", name: "Night shift", placements: 3, pinned_versions: [] },
              ],
            },
            consumer_count: 2,
          },
        },
      }),
      reply(204, null),
    );
    const at = "2026-11-12T03:10:00.123456Z";
    const refused = await retireItem(missionIdReader("m"), "lib-1", 3, at);
    const used = refused.ok ? null : usedByOf(refused.error);
    expect(used && usedInWords(used)).toBe("Used in 2 dashboards: Bus overview, Night shift.");
    expect((await retireItem(missionIdReader("m"), "lib-1", 3, at)).ok).toBe(true);
    // Both guards ride along (dashboards/domain: a rename adds no version).
    expect(String(fetchMock.mock.calls[1]?.[0])).toContain(
      "expected_version=3&expected_updated_at=2026-11-12T03%3A10%3A00.123456Z",
    );
    expect(usedInWords([])).toBe("Not used in any dashboard.");
    // Undecodable in-use details: an error to show, never "unused".
    expect(
      usedByOf({
        kind: "conflict",
        code: "library_item_in_use",
        message: "",
        details: { used_by: 3 },
      }),
    ).toBeNull();
  });

  it("previews a definition without evaluating it", () => {
    expect(previewOf(detail.version.definition_json)).toEqual({
      kind: "Value tile",
      title: "VBAT",
      // qa 13:36Z: a context-scoped binding is bound, to the dashboard's spacecraft.
      reads: [{ point: "EPS.VBAT", on: "on the dashboard's spacecraft" }],
      settings: ["precision: 2", "sampling: latest"],
    });
    const scoped = (mode: string) =>
      previewOf(
        JSON.stringify({
          widget_type_id: "cadence.time_series",
          binding: { observables: ["EPS.VBAT"], scope_mode: mode },
        }),
      )?.reads;
    expect(scoped("override")).toEqual([
      { point: "EPS.VBAT", on: "on one spacecraft, chosen where it's placed" },
    ]);
    expect(scoped("repeat")).toEqual([
      {
        point: "EPS.VBAT",
        on: "on each spacecraft or resource it repeats over, chosen where it's placed",
      },
    ]);
    expect(scoped("brand_new")).toEqual([{ point: "EPS.VBAT", on: null }]);
    expect(previewOf("not json")).toBeNull();
  });

  it("the picker emits the seam {library_item_id, version, name}", async () => {
    stub(reply(200, { data: list([row("a")]) }));
    const w = mount(LibraryPicker, { props: { missionId: missionIdReader("m") } });
    await flushPromises();
    await w.get('button[aria-label="Insert Battery tile a"]').trigger("click");
    expect(w.emitted("pick")?.[0]).toEqual([
      { library_item_id: "a", version: 3, name: "Battery tile a" },
    ]);
    w.unmount();
  });
});
