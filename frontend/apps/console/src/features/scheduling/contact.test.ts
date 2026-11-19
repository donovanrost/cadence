import { describe, expect, it } from "vite-plus/test";
import { contactState, contactStateWord, sourceLabel } from "./contact.ts";

const row = {
  id: "provider_reservation_1",
  kind: "contact",
  state: "confirmed",
  pass_phase: "scheduled",
  delivery_state: "pending",
  spacecraft_id: "spacecraft-earendil-312",
  station: { ref: "SVL", id: null, code: null, name: null },
  antenna: { id: "ant-3", label: null },
  starts_at: "2026-11-08T02:00:00Z",
  ends_at: "2026-11-08T02:10:00Z",
  uplink_capable: null,
  source: { provider: "provider_1", provider_name: "Simulator", synthetic: true },
  max_elevation_deg: null,
  cost: null,
  plan: { id: "contact_plan_1", version: 42 },
  reservation_id: "provider_reservation_1",
  scheduled_contact_id: null,
};

describe("contact state", () => {
  it("maps reservation lifecycle and pass phase onto the UI model", () => {
    expect(contactState({ state: "requesting", pass_phase: null })).toBe("requesting");
    expect(contactState({ state: "pending", pass_phase: null })).toBe("requested");
    expect(contactState({ state: "confirmed", pass_phase: "pass" })).toBe("in_contact");
    expect(contactState({ state: "completed", pass_phase: "closed" })).toBe("ended");
    expect(contactState({ state: "failed", pass_phase: null })).toBe("unknown");
  });

  it("says a cancel is in flight until the provider confirms it (ux)", () => {
    expect(contactStateWord[contactState({ state: "canceling", pass_phase: null })]).toBe(
      "Canceling",
    );
    expect(contactStateWord[contactState({ state: "canceled", pass_phase: null })]).toBe(
      "Canceled",
    );
  });

  it("names the simulator honestly", () => {
    expect(sourceLabel(row.source, "contact")).toBe("SIMULATOR · SYNTHETIC WINDOW");
  });
});
