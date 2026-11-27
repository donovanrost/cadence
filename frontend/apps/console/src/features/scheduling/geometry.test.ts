import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode, decoders as d } from "@/api";
import AlternativesList from "./AlternativesList.vue";
import { alternativesReader } from "./api.ts";
import {
  elevationFact,
  elevationWords,
  geometryLine,
  NO_PREDICTED_PASS,
  offerGeometry,
  passGeometry,
  type OfferGeometry,
} from "./geometry.ts";
import NoPredictedPassNote from "./NoPredictedPassNote.vue";

/** #895 (contacts.md § Elevation, scheduling.md S4): predicted geometry, shown, never computed. */
const pass = d.object(passGeometry);
const offer = d.object(offerGeometry);
const geometry = (over: Record<string, unknown> = {}): OfferGeometry => {
  const r = decode(offer, {
    max_elevation_deg: 41.73,
    elevation_source: "predicted",
    predicted_pass_id: "predicted_pass_1",
    tca: "2026-11-27T00:46:30Z",
    no_predicted_pass: false,
    ...over,
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
};

describe("geometry decoding", () => {
  it("reads the source as a closed vocabulary that tolerates a new value, and every key as nullable", () => {
    expect(geometry().elevation_source).toBe("predicted");
    expect(geometry({ elevation_source: "provider" }).elevation_source).toBe("provider");
    expect(geometry({ elevation_source: "radar" }).elevation_source).toBe("unrecognized");
    const none = {
      max_elevation_deg: null,
      elevation_source: null,
      predicted_pass_id: null,
      tca: null,
      no_predicted_pass: null,
    };
    expect(decode(offer, none).ok).toBe(true);
    expect(decode(pass, { max_elevation_deg: null }).ok).toBe(false);
  });
});

describe("elevation words (#895: a predicted elevation is marked as predicted)", () => {
  it("shows the provider's plain and the prediction's marked, and nothing when neither knows", () => {
    expect(elevationWords(geometry({ elevation_source: "provider" }))).toBe("41.7°");
    expect(elevationWords(geometry())).toBe("41.7° predicted");
    expect(elevationWords(geometry({ elevation_source: "radar" }))).toBe("41.7°");
    expect(elevationWords(geometry({ max_elevation_deg: null, elevation_source: null }))).toBe(
      null,
    );
    expect(elevationFact(geometry())).toEqual([
      { key: "el", label: "Max el", value: "41.7° predicted", mono: true },
    ]);
    expect(elevationFact(geometry({ max_elevation_deg: null }))).toEqual([]);
  });

  it("puts an offer's elevation with its TCA", () => {
    expect(geometryLine(geometry())).toBe("Max el 41.7° predicted · TCA 00:46Z");
    expect(geometryLine(geometry({ tca: null }))).toBe("Max el 41.7° predicted");
    expect(
      geometryLine(geometry({ max_elevation_deg: null, elevation_source: null, tca: null })),
    ).toBeNull();
  });
});

describe("NoPredictedPassNote", () => {
  it("says the caution only when prediction covers the window and no pass backs it", () => {
    const shown = mount(NoPredictedPassNote, {
      props: { geometry: geometry({ no_predicted_pass: true }) },
    });
    expect(shown.text()).toBe(NO_PREDICTED_PASS);
    expect(shown.find(".ap-mark--caution").exists()).toBe(true);
    shown.unmount();
    for (const flag of [false, null]) {
      const w = mount(NoPredictedPassNote, {
        props: { geometry: geometry({ no_predicted_pass: flag }) },
      });
      expect(w.find("[data-no-predicted-pass]").exists()).toBe(false);
      w.unmount();
    }
  });
});

describe("AlternativesList geometry (scheduling.md S4)", () => {
  it("shows each window's elevation and TCA, and the caution where no pass backs it", () => {
    const alt = (id: string, start: string, over: Record<string, unknown>) => ({
      snapshot_id: id,
      requirement_id: null,
      station: { ref: "sva", id: "gs_1", code: "SVA", name: "Svalbard" },
      starts_at: start,
      ends_at: start.replace(":00:00Z", ":08:00Z"),
      synthetic: false,
      max_elevation_deg: 41.73,
      elevation_source: "predicted",
      predicted_pass_id: "predicted_pass_1",
      tca: "2026-11-27T00:04:00Z",
      no_predicted_pass: false,
      effect: {
        rule_met_after: true,
        contacts_after: { have: 3, need: 3 },
        clashes_with: [],
        longest_gap_after_seconds: null,
      },
      ...over,
    });
    const r = decode(alternativesReader, {
      plan_id: "contact_plan_1",
      version: 2,
      spacecraft_id: "sc-1",
      rule_met: false,
      contacts: { have: 2, need: 3 },
      longest_gap: null,
      alternatives: [
        alt("s1", "2026-11-27T00:00:00Z", {}),
        alt("s2", "2026-11-27T06:00:00Z", {
          max_elevation_deg: null,
          elevation_source: null,
          predicted_pass_id: null,
          tca: null,
          no_predicted_pass: true,
        }),
      ],
    });
    if (!r.ok) throw new Error(JSON.stringify(r.error));
    const w = mount(AlternativesList, {
      props: {
        state: { status: "ready", value: r.value, receivedAt: new Date(), requestedAt: new Date() },
        editable: false,
        busy: false,
        name: "EARENDIL-001",
      },
    });
    const rows = w.findAll("li");
    expect(rows[0]?.text()).toContain("Max el 41.7° predicted · TCA 00:04Z");
    expect(rows[0]?.find("[data-no-predicted-pass]").exists()).toBe(false);
    expect(rows[1]?.text()).not.toContain("Max el");
    expect(rows[1]?.text()).toContain(NO_PREDICTED_PASS);
    w.unmount();
  });
});
