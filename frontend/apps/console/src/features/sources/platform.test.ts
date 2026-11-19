import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import type { DataSource } from "./api.ts";
import {
  blastRadiusReader,
  type BindingEvent,
  type BlastRadius,
  type MissionBinding,
} from "./bindings.ts";
import {
  bindingNoun,
  blastLine,
  blockedReason,
  changedLine,
  countsDiffer,
  eventLine,
  historyWho,
  livePassesLine,
  platformTargets,
  outcomeLine,
  sheetTitle,
  switchLabel,
  switchReady,
  visibleBindings,
} from "./platform.ts";

const now = new Date("2026-11-14T03:20:00Z");
const pass = (spacecraft_name: string, station_code: string | null, aos: string) => ({
  spacecraft_name,
  station_code,
  aos,
});
function radius(affected: number, total: number, first: unknown[] = []): BlastRadius {
  const r = decode(blastRadiusReader, {
    binding: {
      id: "b1",
      logical_source: "default_flight_telemetry",
      realm: "flight",
      from: { id: "s1", display_name: "Cadence managed store" },
    },
    affected_missions: affected,
    live_passes: { total, first },
  });
  if (!r.ok) throw r.error;
  return r.value;
}

describe("U53 platform binding switch words (ux)", () => {
  it("names the binding's data and the blast radius", () => {
    expect(bindingNoun("default_flight_telemetry")).toBe("telemetry");
    expect(bindingNoun("default_flight_operational_observables")).toBe("operational observables");
    expect(sheetTitle("default_flight_telemetry", 12)).toBe(
      "Switch default_flight_telemetry for 12 missions?",
    );
    expect(blastLine(radius(12, 0), "Northlight archive")).toBe(
      "This changes telemetry for all 12 missions that use it. They'll read from Northlight archive instead of Cadence managed store.",
    );
    expect(blastLine(radius(1, 0), null)).toBe(
      "This changes telemetry for the one mission that uses it.",
    );
    expect(switchLabel(12)).toBe("Switch for 12 missions");
    expect(switchLabel(1)).toBe("Switch for 1 mission");
  });

  it("lists up to three live passes, then 'and K more'; none: no line", () => {
    expect(livePassesLine(radius(12, 0), now)).toBeNull();
    const three = [
      pass("EARENDIL-312", "SVA", "2026-11-14T03:10:00Z"),
      pass("EARENDIL-008", "SVB", "2026-11-14T03:12:00Z"),
      pass("EARENDIL-401", "KSAT", "2026-11-14T03:14:00Z"),
    ];
    expect(livePassesLine(radius(12, 3, three), now)).toBe(
      "3 passes are live right now, and their telemetry switches mid-pass: EARENDIL-312 · SVA 03:10Z, EARENDIL-008 · SVB 03:12Z, EARENDIL-401 · KSAT 03:14Z.",
    );
    expect(livePassesLine(radius(12, 7, three), now)).toBe(
      "7 passes are live right now, and their telemetry switches mid-pass: EARENDIL-312 · SVA 03:10Z, EARENDIL-008 · SVB 03:12Z, EARENDIL-401 · KSAT 03:14Z and 4 more.",
    );
    expect(
      livePassesLine(radius(2, 1, [pass("EARENDIL-312", null, "2026-11-13T23:58:00Z")]), now),
    ).toBe("1 pass is live right now, and its telemetry switches mid-pass: EARENDIL-312.");
    expect(
      livePassesLine(radius(2, 1, [pass("EARENDIL-312", "SVA", "2026-11-13T23:58:00Z")]), now),
    ).toBe(
      "1 pass is live right now, and its telemetry switches mid-pass: EARENDIL-312 · SVA 11-13 23:58Z.",
    );
  });

  it("says what changed on 409 blast_radius_changed, and when the typed name must clear", () => {
    expect(changedLine(radius(12, 4))).toBe(
      "This changed while you were confirming: it now affects 12 missions and 4 live passes.",
    );
    expect(changedLine(radius(1, 1))).toBe(
      "This changed while you were confirming: it now affects 1 mission and 1 live pass.",
    );
    expect(countsDiffer(radius(12, 3), radius(12, 4))).toBe(true);
    expect(countsDiffer(radius(12, 3), radius(12, 3))).toBe(false);
    expect(countsDiffer(null, radius(12, 3))).toBe(false);
  });

  it("enables the switch only with a reason, the exact name and another source", () => {
    const f = {
      reason: "Northlight cutover",
      typed: "default_flight_telemetry",
      name: "default_flight_telemetry",
      target: "s2",
      current: "s1",
    };
    expect(switchReady(f)).toBe(true);
    expect(switchReady({ ...f, reason: "  " })).toBe(false);
    expect(blockedReason({ ...f, reason: "" })).toBe("Give a reason first.");
    expect(switchReady({ ...f, typed: "Default_flight_telemetry" })).toBe(false);
    expect(blockedReason({ ...f, typed: "x" })).toBe("Type default_flight_telemetry to confirm.");
    expect(switchReady({ ...f, target: "s1" })).toBe(false);
    expect(blockedReason({ ...f, target: "s1" })).toBe("Choose another source.");
    // ux: the first missing field in the sheet's order, top to bottom: source, reason, name.
    expect(blockedReason({ ...f, target: "s1", reason: "", typed: "" })).toBe(
      "Choose another source.",
    );
    expect(blockedReason({ ...f, reason: "", typed: "" })).toBe("Give a reason first.");
  });

  it("names both sides by display name, the picker's name for the current source first", () => {
    const r = radius(12, 0);
    expect(blastLine(r, "Northlight archive", "Cadence managed store")).toBe(
      "This changes telemetry for all 12 missions that use it. They'll read from Northlight archive instead of Cadence managed store.",
    );
    expect(blastLine(r, null, "Cadence managed store")).toBe(
      "This changes telemetry for all 12 missions that use it.",
    );
  });

  it("reports the outcome from the recorded counts", () => {
    expect(outcomeLine("default_flight_telemetry", "Northlight archive", 12)).toBe(
      "Switched default_flight_telemetry to Northlight archive. 12 missions read from it now.",
    );
    expect(outcomeLine("default_flight_telemetry", "Northlight archive", 1)).toBe(
      "Switched default_flight_telemetry to Northlight archive. One mission reads from it now.",
    );
  });

  it("hides platform rows until the toggle is on", () => {
    const row = (id: string, shared: boolean): MissionBinding => ({
      id,
      logical_source: "default_flight_telemetry",
      realm: "flight",
      data_source: { id: "s1", display_name: "Store" },
      status: "active",
      shared,
    });
    const rows = [row("own", false), row("platform", true)];
    expect(visibleBindings(rows, false).map((b) => b.id)).toEqual(["own"]);
    expect(visibleBindings(rows, true).map((b) => b.id)).toEqual(["own", "platform"]);
  });

  it("writes the audit line for a platform switch and short lines otherwise", () => {
    const base: BindingEvent = {
      at: "2026-11-14T03:21:00Z",
      actor: { kind: "user", id: "u1", name: "Mira K." },
      kind: "switched",
      from: { id: "s1", display_name: "Cadence managed store" },
      to: { id: "s2", display_name: "Northlight archive" },
      reason: "Northlight cutover",
      affected_missions: 12,
      live_passes_total: 3,
    };
    expect(eventLine(base, "default_flight_telemetry")).toBe(
      "Switched platform binding default_flight_telemetry from Cadence managed store to Northlight archive · 12 missions, 3 live passes: “Northlight cutover”",
    );
    expect(
      eventLine(
        { ...base, reason: null, affected_missions: null, live_passes_total: null },
        "default_flight_telemetry",
      ),
    ).toBe("Switched from Cadence managed store to Northlight archive.");
    expect(
      eventLine(
        {
          ...base,
          to: { id: "s3", display_name: null },
          reason: null,
          affected_missions: null,
          live_passes_total: null,
        },
        "x",
      ),
    ).toBe("Switched from Cadence managed store to an unknown source.");
    expect(eventLine({ ...base, kind: "disabled" }, "x")).toBe("Disabled.");
    expect(eventLine({ ...base, kind: { unrecognized: "re_pointed" } }, "x")).toBe("re pointed");
  });

  it("names a platform admin when a platform-wide binding's event comes without its actor", () => {
    const e: BindingEvent = {
      at: "2026-11-14T03:21:00Z",
      actor: null,
      kind: "switched",
      from: null,
      to: { id: "s2", display_name: "Northlight archive" },
      reason: null,
      affected_missions: null,
      live_passes_total: null,
    };
    expect(historyWho(e, true)).toBe("A platform admin");
    expect(historyWho(e, false)).toBe("Cadence");
    expect(historyWho({ ...e, actor: { kind: "user", id: "u1", name: "Mira K." } }, true)).toBe(
      "Mira K.",
    );
  });
});

describe("platformTargets (api-ops: 422 platform_target_required)", () => {
  const src = (id: string, over: Partial<DataSource> = {}): DataSource => ({
    id,
    display_name: id,
    kind: "byo_tsdb",
    owner: "customer",
    health: { status: "healthy", checked_at: "2026-11-13T01:00:00Z" },
    last_received_at: null,
    expected_interval_s: null,
    stale: null,
    credentials: null,
    state: "enabled",
    logical_source: { key: "flight_telemetry", label: "Flight telemetry" },
    isolation_level: "customer_owned",
    storage: "questdb",
    credentials_ref: null,
    shared: true,
    tsdb_actions: undefined,
    ...over,
  });
  it("offers only other active platform-shared sources of the same logical source", () => {
    const sources = [
      src("current"),
      src("archive"),
      src("own", { shared: false }),
      src("off", { state: "disabled" }),
      src("other", { logical_source: { key: "events", label: "Events" } }),
    ];
    const current = { data_source_id: "current", logical_source: "flight_telemetry" };
    expect(platformTargets(sources, current).map((s) => s.id)).toEqual(["archive"]);
  });
});
