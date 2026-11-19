import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import type { ApiError } from "@/api";
import FailureOutcomeCallout from "./FailureOutcomeCallout.vue";
import { refusalOutcome } from "./refusals.ts";

/** api's 409 in_use (domain 16ee2ed00): every kind present, items ≤ 3, counts full. */
const none = { count: 0, items: [] };
const uses = (extra: Record<string, unknown> = {}) => ({
  routes: none,
  profile_routes: none,
  booked_passes: { count: 0, next_at: null },
  listening_now: none,
  transports: none,
  ...extra,
});
const inUse = (u: Record<string, unknown>, name: string | null = "INU S-band"): ApiError => ({
  kind: "conflict",
  code: "in_use",
  message: "in use",
  details: { entity: { kind: "transport", id: "t-1", name }, uses: u },
});
const sc = { id: "sc-312", name: "EARENDIL-312" };
const inu = { id: "gs-1", code: "INU", name: "Inuvik" };

describe("in-use refusal (ux U82)", () => {
  it("names each kind of use, up to three, then 'and N more', and closes at stage", () => {
    const o = refusalOutcome(
      inUse(
        uses({
          routes: {
            count: 6,
            items: [
              {
                routing_rule_id: "r1",
                name: "Inuvik (Demo)",
                spacecraft: sc,
                station: inu,
                direction: "downlink",
              },
              {
                routing_rule_id: "r2",
                name: null,
                spacecraft: sc,
                station: inu,
                direction: "uplink",
              },
            ],
          },
          profile_routes: {
            count: 1,
            items: [
              { profile: { id: "p1", name: "Earendil standard" }, rule_id: "x", label: null },
            ],
          },
          booked_passes: { count: 2, next_at: "2026-11-17T03:10:00Z" },
          listening_now: {
            count: 1,
            items: [
              {
                realized_contact_id: "rc-1",
                spacecraft: sc,
                station_code: "FBK",
                starts_at: "2026-11-17T03:10:00Z",
              },
            ],
          },
        }),
      ),
      "staged",
    );
    expect(o.sentence).toBe("INU S-band is still in use, so it can't be archived:");
    expect(o.closing).toBe("Move or remove these first.");
    expect(o.uses?.map((l) => [l.label, l.items.map((i) => i.text), l.more])).toEqual([
      ["Routes", ["EARENDIL-312 · Inuvik (Demo) — downlink", "EARENDIL-312 · INU uplink"], 4],
      ["Profile routes", ["Earendil standard"], 0],
      ["Booked passes", ["2, the next at 11-17 03:10Z"], 0],
      ["Listening now", ["the EARENDIL-312 FBK 03:10Z pass"], 0],
    ]);
    expect(o.uses?.[0]?.items[0]?.to).toEqual({
      name: "setup.spacecraft.one",
      params: { spacecraftId: "sc-312" },
    });
  });

  it("words the apply-time refusal for the change set, and an all-zero one with no list", () => {
    const transports = { count: 2, items: [{ id: "t-1", name: "INU S-band" }] };
    const atApply = refusalOutcome(inUse(uses({ transports }), "Inuvik · INU"), "applied");
    expect(atApply.sentence).toBe(
      "Inuvik · INU is in use now, so this change set can't be applied:",
    );
    expect(atApply.closing).toBe("Move these first, or take the archive out of the change set.");
    expect(atApply.uses?.[0]).toMatchObject({ label: "Transports", more: 1 });
    const empty = refusalOutcome(inUse(uses(), null), "staged");
    expect(empty).toMatchObject({
      sentence: "This transport is still in use, so it can't be archived.",
      closing: "Something still uses it.",
    });
    expect(empty.uses).toBeUndefined();
  });

  it("leaves every other failure to failureOutcome", () => {
    const o = refusalOutcome({ kind: "unavailable", status: 0, message: "offline" }, "staged");
    expect(o.changed).toBeNull();
    expect(o.uses).toBeUndefined();
  });

  it("renders the lines, their links and the closing in the callout", () => {
    const o = refusalOutcome(
      inUse(
        uses({
          routes: {
            count: 1,
            items: [
              {
                routing_rule_id: "r1",
                name: null,
                spacecraft: sc,
                station: inu,
                direction: "downlink",
              },
            ],
          },
        }),
      ),
      "staged",
    );
    const w = mount(FailureOutcomeCallout, {
      props: { outcome: o },
      global: { stubs: { RouterLink: { template: "<a><slot /></a>" } } },
    });
    expect(w.find("li").text()).toBe("Routes: EARENDIL-312 · INU downlink");
    expect(w.find("li a").text()).toBe("EARENDIL-312 · INU downlink");
    expect(w.text()).toContain("Move or remove these first.");
  });
});
