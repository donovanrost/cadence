import { flushPromises } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { effectScope, ref } from "vue";
import { missionId, scid, pointId as pointIdReader } from "@/api/index.ts";
import { spacecraftRow } from "@/features/fleet/index.ts";
import { parseWindow } from "./window.ts";
import { useSeries } from "./useSeries.ts";

vi.mock("@/live/index.ts", () => ({ useMissionInvalidation: () => undefined }));

afterEach(() => vi.unstubAllGlobals());

const historyBody = (point: string) => ({
  data: {
    point_id: point,
    unit: "V",
    description: null,
    spacecraft_id: spacecraftRow(1).id,
    from: "2026-11-16T09:00:00Z",
    to: "2026-11-16T10:00:00Z",
    bucket_width_ms: 60_000,
    truncated: false,
    buckets: [],
  },
});

describe("Telemetry series (ux, §11c(D))", () => {
  it("keeps the last plot of the same selection when a re-read fails, and starts over on a new one", async () => {
    let fail = false;
    vi.stubGlobal("fetch", (input: string) =>
      Promise.resolve(
        fail
          ? new Response(JSON.stringify({ error: { code: "unavailable", message: "Down." } }), {
              status: 503,
            })
          : new Response(
              JSON.stringify(historyBody(input.includes("EPS.IBAT") ? "EPS.IBAT" : "EPS.VBAT")),
            ),
      ),
    );
    const series = ref([{ scid: scid(1), pointId: pointIdReader("EPS.VBAT") }]);
    const scope = effectScope();
    const q = scope.run(() =>
      useSeries(ref(missionId("m-1")), series, ref([spacecraftRow(1)]), ref(parseWindow({}, "6h"))),
    );
    if (!q) throw new Error("no scope");
    await flushPromises();
    expect(q.state.value.status).toBe("ready");
    expect(q.refreshFailed.value).toBeNull();

    fail = true;
    q.refetch();
    await flushPromises();
    expect(q.state.value.status).toBe("ready");
    expect(q.refreshFailed.value?.readAt).toBeInstanceOf(Date);

    series.value = [{ scid: scid(1), pointId: pointIdReader("EPS.IBAT") }];
    await flushPromises();
    expect(q.state.value.status).toBe("failed");
    expect(q.refreshFailed.value).toBeNull();
    scope.stop();
  });
});
