import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode, type ApiError } from "@/api/index.ts";
import { noteFor } from "@/features/scheduling/index.ts";
import { repairInfoReader } from "@/features/scheduling/repair-info.ts";
import { replanErrorText } from "./errors.ts";
import ReplanWindowMeta from "./ReplanWindowMeta.vue";
import { hoursWord, windowMeta } from "./windowMeta.ts";

const NOW = new Date("2026-11-17T02:50:00Z");
const repair = (o: Record<string, unknown> = {}) => {
  const r = decode(repairInfoReader, {
    window: { from: "2026-11-17T02:45:00Z", to: "2026-11-17T10:45:00Z" },
    horizon_seconds: 28800,
    attempts: { used: 1, max: 3 },
    available: true,
    cause: null,
    ...o,
  });
  if (!r.ok) throw r.error;
  return r.value;
};

/** ux U76: Re-plan's header meta (K2). */
describe("the re-plan window line (U76)", () => {
  it("window, horizon and attempt; no cause, no clause", () => {
    expect(windowMeta(repair(), NOW)).toEqual({
      text: "Window 02:45–10:45Z · 8 h by the planning policy · attempt 2 of 3",
      last: false,
      noneLeft: null,
    });
  });

  it("names the cause when api sends it", () => {
    const provider = repair({
      cause: {
        kind: "provider_change",
        provider_name: "Northlight",
        station_name: null,
        since: "2026-11-17T02:45:00Z",
      },
    });
    expect(windowMeta(provider, NOW).text).toBe(
      "Window 02:45–10:45Z · from Northlight's change at 02:45Z · 8 h by the planning policy · attempt 2 of 3",
    );
    const outage = repair({
      cause: {
        kind: "station_outage",
        provider_name: null,
        station_name: "SVA",
        since: "2026-11-17T02:45:00Z",
      },
    });
    expect(windowMeta(outage, NOW).text).toContain("from the station outage at 02:45Z");
  });

  it("the last attempt reads as caution; with none left it says why", () => {
    const last = windowMeta(repair({ attempts: { used: 2, max: 3 } }), NOW);
    expect(last.text).toContain("attempt 3 of 3, the last the policy allows");
    expect(last.last).toBe(true);
    const none = windowMeta(repair({ attempts: { used: 3, max: 3 }, available: false }), NOW);
    expect(none.text).not.toContain("attempt");
    expect(none.noneLeft).toBe(
      "No re-plan attempts left (3 of 3). The planning policy sets the limit.",
    );
  });

  it("shows the Planning policy link to admins only", () => {
    const props = { repair: repair({ attempts: { used: 3, max: 3 }, available: false }), now: NOW };
    const stubs = { RouterLink: { template: "<a><slot /></a>" } };
    expect(
      mount(ReplanWindowMeta, { props: { ...props, admin: true }, global: { stubs } })
        .find("a")
        .text(),
    ).toBe("Planning policy");
    expect(
      mount(ReplanWindowMeta, { props: { ...props, admin: false }, global: { stubs } })
        .find("a")
        .exists(),
    ).toBe(false);
  });

  it("words durations and the attempt-limit refusal", () => {
    expect(hoursWord(28800)).toBe("8 h");
    expect(hoursWord(5400)).toBe("1 h 30 min");
    const refused: ApiError = {
      kind: "conflict",
      code: "fleet_repair_attempt_limit_exceeded",
      message: "x",
      details: { used: 3, max: 3 },
    };
    expect(replanErrorText(refused)).toBe(
      "No re-plan attempts left (3 of 3). The planning policy sets the limit.",
    );
  });
});

describe("where a Submit's note goes (U76)", () => {
  it("approving a pending plan records it on the decision; any other submit, with the submission", () => {
    expect(noteFor({ state: "pending_approval" }, "Checked with ops.")).toEqual({
      key: "decision_note",
      text: "Checked with ops.",
    });
    expect(noteFor({ state: "draft" }, "Moved 004 to KIR.")).toEqual({
      key: "note",
      text: "Moved 004 to KIR.",
    });
    expect(noteFor({ state: "draft" }, "")).toBeUndefined();
  });
});
