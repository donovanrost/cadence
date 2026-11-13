import { flushPromises, mount } from "@vue/test-utils";
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
      '{"type":"value_tile","title":"VBAT","observables":["EPS.VBAT"],"precision":2}',
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
    const l = await fetchLibrary("m", { q: "", page: 1 });
    expect(l.ok && l.value.items.map((r) => kindWord(r.kind))).toEqual([
      "Value tile",
      "sky plot",
      "acme.gauge",
    ]);
    const item = await fetchLibraryItem("m", "lib-1", null);
    expect(item.ok && item.value.used_by.dashboards[0]?.name).toBe("Bus overview");
  });

  it("delete: 409 in use names the dashboards; 204 retires", async () => {
    stub(
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
    const refused = await retireItem("m", "lib-1", 3);
    const used = refused.ok ? null : usedByOf(refused.error);
    expect(used && usedInWords(used)).toBe("Used in 2 dashboards: Bus overview, Night shift.");
    expect((await retireItem("m", "lib-1", 3)).ok).toBe(true);
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
      reads: ["EPS.VBAT"],
      settings: ["precision: 2"],
    });
    expect(previewOf("not json")).toBeNull();
  });

  it("the picker emits the seam {library_item_id, version, name}", async () => {
    stub(reply(200, { data: list([row("a")]) }));
    const w = mount(LibraryPicker, { props: { missionId: "m" } });
    await flushPromises();
    await w.get('button[aria-label="Insert Battery tile a"]').trigger("click");
    expect(w.emitted("pick")?.[0]).toEqual([
      { library_item_id: "a", version: 3, name: "Battery tile a" },
    ]);
    w.unmount();
  });
});
