import { effectScope, nextTick, ref } from "vue";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId as missionIdReader } from "@/api/index.ts";
import { fetchSpacecraftDirectory } from "./api.ts";
import { useSpacecraftDirectory } from "./useSpacecraftDirectory.ts";

vi.mock("@/live", () => ({ useMissionInvalidation: () => undefined }));

const wireRow = (n: number) => ({
  id: `sc-${String(n).padStart(4, "0")}`,
  name: `Craft ${String(n).padStart(4, "0")}`,
  scid: null,
  norad_id: null,
  plane: null,
  slot: null,
  profile: null,
  routing_rule_count: 0,
  ready: false,
  last_received_at: null,
});

/** A server holding `total` spacecraft, `size` to a page, answering by cursor (the first index). */
function server(total: number, size: number) {
  const urls: string[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn((input: string) => {
      urls.push(input);
      const url = new URL(input, "http://x");
      const cursor = url.searchParams.get("cursor");
      const page = Math.min(size, Number(url.searchParams.get("limit")));
      const from = cursor === null ? 0 : Number(cursor);
      const to = Math.min(from + page, total);
      const body = {
        data: {
          spacecraft: Array.from({ length: to - from }, (_, i) => wireRow(from + i)),
          telemetry: "ok",
          // The mission's counts and SCIDs come with the first page only (#933).
          ...(cursor === null
            ? {
                summary: {
                  total,
                  profiles: 0,
                  without_profile: total,
                  without_scid: total,
                  without_routing_rule: total,
                  awaiting_first_aos: total,
                },
                scids_in_use: [],
                next_free_scid: 1,
              }
            : {}),
        },
        meta: { next_cursor: to < total ? String(to) : null },
      };
      return Promise.resolve(
        new Response(JSON.stringify(body), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      );
    }),
  );
  return urls;
}

const flush = async () => {
  for (let i = 0; i < 12; i++) await Promise.resolve();
  await nextTick();
};

afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

describe("useSpacecraftDirectory (#796)", () => {
  it("holds a page with the whole mission's summary and appends the next on Load more", async () => {
    const urls = server(450, 200);
    const scope = effectScope();
    const dir = scope.run(() => useSpacecraftDirectory(ref(missionIdReader("m")), ref("")));
    if (!dir) throw new Error("no directory");
    await flush();

    const first = dir.state.value;
    if (first.status !== "ready") throw new Error("not ready");
    expect(first.value.items).toHaveLength(200);
    // The count is the server's: 200 rows shown never reads as the whole fleet.
    expect(first.value.meta.summary?.total).toBe(450);
    expect(first.value.next).toBe("200");

    await dir.more();
    await flush();
    await dir.more();
    await flush();
    const last = dir.state.value;
    if (last.status !== "ready") throw new Error("not ready");
    expect(last.value.items).toHaveLength(450);
    expect(last.value.next).toBeNull();
    expect(urls[0]).toContain("limit=200");
    expect(urls[1]).toContain("cursor=200");
    // The first page's counts stay while later pages (which send none) are appended.
    expect(last.value.meta.summary?.total).toBe(450);
    scope.stop();
  });

  it("asks the server to filter, settled after typing stops, and starts over at the first page", async () => {
    vi.useFakeTimers();
    const urls = server(450, 200);
    const query = ref("");
    const scope = effectScope();
    const dir = scope.run(() => useSpacecraftDirectory(ref(missionIdReader("m")), query));
    if (!dir) throw new Error("no directory");
    await vi.advanceTimersByTimeAsync(0);
    await flush();
    expect(urls).toHaveLength(1);

    query.value = "earen";
    query.value = "earendil ";
    await flush();
    // Still typing: nothing asked yet.
    expect(urls).toHaveLength(1);
    await vi.advanceTimersByTimeAsync(300);
    await flush();
    expect(urls).toHaveLength(2);
    expect(urls[1]).toContain("q=earendil");
    expect(urls[1]).not.toContain("cursor=");
    expect(dir.settledQuery.value).toBe("earendil");
    scope.stop();
  });
});

describe("fetchSpacecraftDirectory (every page, for the pickers)", () => {
  it("walks the pages in 500-row requests and returns every active spacecraft once", async () => {
    const urls = server(1_200, 500);
    const r = await fetchSpacecraftDirectory(missionIdReader("m"), new AbortController().signal);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.value.spacecraft).toHaveLength(1_200);
    expect(new Set(r.value.spacecraft.map((s) => s.id)).size).toBe(1_200);
    expect(urls).toHaveLength(3);
    expect(urls.every((u) => u.includes("limit=500"))).toBe(true);
    expect(r.value.scids).toEqual({ next: 1, inUse: [] });
  });

  it("stops a runaway cursor instead of looping", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(() =>
        Promise.resolve(
          new Response(
            JSON.stringify({
              data: {
                spacecraft: [],
                summary: {
                  total: 0,
                  profiles: 0,
                  without_profile: 0,
                  without_scid: 0,
                  without_routing_rule: 0,
                  awaiting_first_aos: 0,
                },
                telemetry: "ok",
              },
              meta: { next_cursor: "again" },
            }),
            { status: 200, headers: { "content-type": "application/json" } },
          ),
        ),
      ),
    );
    const r = await fetchSpacecraftDirectory(missionIdReader("m"), new AbortController().signal);
    expect(r.ok).toBe(false);
  });
});
