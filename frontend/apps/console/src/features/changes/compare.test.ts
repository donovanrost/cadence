import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId as missionIdReader } from "@/api/index.ts";
import { fetchComparison } from "./compare.ts";

afterEach(() => vi.unstubAllGlobals());

describe("fetchComparison", () => {
  it("maps compare entries into revision entries (latest touching revision, field paths)", async () => {
    vi.stubGlobal("fetch", () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            data: {
              from: 6,
              to: 8,
              entries: [
                {
                  entity_id: "spacecraft-earendil-001",
                  fields: [{ after: 6, before: 4, path: "spacecraft_type_version" }],
                  kind: "spacecraft",
                  op: "update",
                  revisions: [7, 8],
                },
              ],
            },
          }),
          { status: 200 },
        ),
      ),
    );
    const r = await fetchComparison(
      { missionId: missionIdReader("m"), from: 6, to: 8 },
      new AbortController().signal,
    );
    if (!r.ok) throw new Error("failed");
    expect(r.value.entries[0]).toMatchObject({
      revision: 8,
      revisions: [7, 8],
      paths: ["spacecraft_type_version"],
      entity_name: null,
    });
  });
});
