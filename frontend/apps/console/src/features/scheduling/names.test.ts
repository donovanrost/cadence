import { flushPromises } from "@vue/test-utils";
import { effectScope, ref } from "vue";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import type { MissionId } from "@/api/index.ts";
import { useSpacecraftNames } from "./names.ts";

vi.mock("@/live/index.ts", () => ({ useMissionInvalidation: () => undefined }));

const page = (names: { id: string; name: string; scid: number | null }[], next: string | null) =>
  new Response(JSON.stringify({ data: { names }, meta: { next_cursor: next } }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });

afterEach(() => vi.unstubAllGlobals());

/** #847: names come from the light names read, every page of it, not the fleet read. */
describe("useSpacecraftNames", () => {
  it("walks every page into one name map, from the names read", async () => {
    const fetch = vi
      .fn<typeof globalThis.fetch>()
      .mockResolvedValueOnce(page([{ id: "sc-1", name: "EARENDIL-001", scid: 101 }], "c1"))
      .mockResolvedValueOnce(page([{ id: "sc-2", name: "EARENDIL-002", scid: null }], null));
    vi.stubGlobal("fetch", fetch);
    const scope = effectScope();
    const nameOf = scope.run(() => useSpacecraftNames(ref("m1" as MissionId)));
    await flushPromises();
    await flushPromises();
    const urls = fetch.mock.calls.map(([input]) =>
      input instanceof Request ? input.url : (input?.toString() ?? ""),
    );
    expect(urls[0]).toContain("/missions/m1/spacecraft/names");
    expect(urls[1]).toContain("/spacecraft/names?cursor=c1");
    expect(urls.some((u) => u.includes("/fleet"))).toBe(false);
    expect(nameOf?.("sc-1")).toEqual({ name: "EARENDIL-001", scid: 101 });
    expect(nameOf?.("sc-2")).toEqual({ name: "EARENDIL-002", scid: null });
    expect(nameOf?.("sc-3")).toBeNull();
    scope.stop();
  });
});
