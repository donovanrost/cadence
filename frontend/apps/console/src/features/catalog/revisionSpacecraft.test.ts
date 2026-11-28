import { flushPromises, mount, RouterLinkStub } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { decode, missionId } from "@/api/index.ts";
import RevisionSpacecraftPanel from "./approval/RevisionSpacecraftPanel.vue";
import {
  craftName,
  revisionSpacecraftReader,
  usesText,
  versionText,
} from "./revisionSpacecraft.ts";

vi.mock("@/live/index.ts", async (original) => ({
  ...(await original<typeof import("@/live/index.ts")>()),
  useMissionInvalidation: () => undefined,
}));
afterEach(() => vi.unstubAllGlobals());

/** Synthetic rows in setup.md's shape (#678, #1036), not captured from a server. */
const TOTAL = 500;
const row = (i: number, o: Record<string, unknown> = {}) => ({
  id: `spacecraft-earendil-${String(i).padStart(3, "0")}`,
  name: `EARENDIL-${String(i).padStart(3, "0")}`,
  scid: i,
  uses: ["saved"],
  configuration_version: 1,
  ...o,
});

function server() {
  const asked: URL[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn((input: string) => {
      const url = new URL(input, "http://x");
      asked.push(url);
      const from = Number(url.searchParams.get("cursor") ?? "0");
      const to = Math.min(from + Number(url.searchParams.get("limit")), TOTAL);
      const body = {
        data: { spacecraft: Array.from({ length: to - from }, (_, i) => row(from + i + 1)) },
        meta: { total: TOTAL, next_cursor: to < TOTAL ? String(to) : null },
      };
      return Promise.resolve(new Response(JSON.stringify(body), { status: 200 }));
    }),
  );
  return asked;
}

describe("a catalog revision's spacecraft (#678)", () => {
  it("words what uses it, its version, and a nameless craft", () => {
    const read = (o: Record<string, unknown>) => {
      const r = decode(revisionSpacecraftReader, row(1, o));
      if (!r.ok) throw new Error(JSON.stringify(r.error));
      return r.value;
    };
    expect(usesText(read({ uses: ["saved", "active"] }))).toBe("Running · Saved configuration");
    expect(usesText(read({ uses: ["saved"] }))).toBe("Saved configuration");
    // A use this console doesn't know says only that it's used.
    expect(usesText(read({ uses: ["staged"] }))).toBe("Used");
    expect(versionText(read({ configuration_version: null }))).toBe("No saved configuration");
    expect(versionText(read({ configuration_version: 3 }))).toBe("v3");
    expect(craftName(read({ name: " " }))).toBe("Unknown spacecraft");
  });

  it("pages 500 spacecraft 200 at a time, counted by the server, each linked by name", async () => {
    const asked = server();
    const w = mount(RevisionSpacecraftPanel, {
      props: { missionId: missionId("m-1"), catalogRevisionId: "catalog_revision_1" },
      global: { stubs: { RouterLink: RouterLinkStub } },
    });
    await flushPromises();
    expect(w.findAll("tbody tr")).toHaveLength(200);
    expect(w.text()).toContain("500 spacecraft");
    expect(w.text()).toContain("200 of 500 shown");
    const first = w.findAllComponents(RouterLinkStub)[0];
    expect(first?.text()).toBe("EARENDIL-001");
    expect(first?.props("to")).toEqual({
      name: "setup.spacecraft.one",
      params: { spacecraftId: "spacecraft-earendil-001" },
    });
    await w
      .findAll("button")
      .find((b) => b.text() === "Load more")
      ?.trigger("click");
    await flushPromises();
    expect(w.findAll("tbody tr")).toHaveLength(400);
    expect(asked.map((u) => [u.pathname, u.searchParams.get("cursor")])).toEqual([
      ["/api/v1/missions/m-1/catalog/revisions/catalog_revision_1/spacecraft", null],
      ["/api/v1/missions/m-1/catalog/revisions/catalog_revision_1/spacecraft", "200"],
    ]);
  });
});
