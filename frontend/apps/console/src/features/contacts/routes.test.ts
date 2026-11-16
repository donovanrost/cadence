import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import {
  rangePresets,
  routeLabel,
  routesReader,
  uplinkBlock,
  uplinkNote,
  viaWords,
  visibleRoutes,
  windowProblem,
  type Route,
} from "./routes.ts";

const route = (key: string, o: Record<string, unknown> = {}): Route => {
  const r = decode(routesReader, {
    spacecraft: { id: "sc", name: "EARENDIL-312" },
    routes: [
      {
        key,
        name: "S-band",
        provider: { id: "nl", name: "Northlight" },
        transport: { id: "t", version: 1, name: null },
        service_name: null,
        station: { ref: "sva", id: "sva", code: "SVA", name: "Svalbard" },
        uplink: true,
        ...o,
      },
    ],
    not_ready: [],
    limits: { max_window_s: 604_800, max_reach_s: 1_209_600, reach_until: "2026-11-30T04:00:00Z" },
  });
  const first = r.ok ? r.value.routes[0] : undefined;
  if (!first) throw new Error("fixture");
  return first;
};
const limits = { max_window_s: 259_200, max_reach_s: 604_800, reach_until: "2026-11-23T04:00:00Z" };

describe("Book a pass routes (ux A16b)", () => {
  it("labels by station, adds the path only when a station has several, and names unpinned ones", () => {
    const a = route("a");
    const b = route("b", { name: "X-band" });
    const free = route("c", { station: null, uplink: null });
    expect(routeLabel(a, [a, free])).toBe("SVA · Northlight");
    expect(routeLabel(a, [a, b])).toBe("SVA · Northlight · S-band");
    expect(routeLabel(free, [a, free])).toBe("Northlight · any of its stations");
    expect(uplinkNote(free)).toBe("uplink varies by station");
    expect(uplinkNote(route("d", { uplink: false }))).toBe("downlink only");
  });
  it("hides downlink-only routes under With uplink, keeps unpinned and chosen ones", () => {
    const down = route("down", {
      uplink: false,
      station: { ref: "kir", id: "kir", code: "KIR", name: null },
    });
    const free = route("free", { station: null, uplink: null });
    const v = visibleRoutes([down, free], true, []);
    expect(v.shown.map((r) => r.key)).toEqual(["free"]);
    expect(v.hidden).toBe(1);
    expect(visibleRoutes([down], true, ["down"]).hidden).toBe(0);
    expect(uplinkBlock([down], ["down"], true, "EARENDIL-312")).toBe(
      "KIR · Northlight has no uplink path to EARENDIL-312. Choose Downlink or another route.",
    );
    expect(uplinkBlock([down, free], ["down", "free"], true, "EARENDIL-312")).toBeNull();
  });
  it("checks the window against the server's reach and length", () => {
    const now = Date.parse("2026-11-16T04:00:00Z");
    expect(windowProblem({ from: now, to: Date.parse("2026-11-24T00:00:00Z") }, limits, now)).toBe(
      "Search up to 7 days ahead (until 11-23 04:00Z).",
    );
    expect(windowProblem({ from: now - 3_600_000, to: now }, limits, now)).toBe(
      "Start from now or later.",
    );
    expect(windowProblem({ from: now, to: now + 4 * 86_400_000 }, limits, now)).toBe(
      "Search a window of up to 3 days.",
    );
    expect(rangePresets(now, "2026-11-18T04:00:00Z").map((p) => p.label)).toEqual([
      "Next 6 h",
      "Next 24 h",
      "Next 48 h",
    ]);
    expect(viaWords([route("a")], ["a"])).toBe(" via SVA · Northlight");
  });
});
