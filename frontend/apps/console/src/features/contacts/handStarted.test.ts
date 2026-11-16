import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { decode, missionId } from "@/api/index.ts";
import ContactRecordView from "./ContactRecordView.vue";
import {
  isHandStarted,
  neverLiveLine,
  passOrContactReader,
  passesWithContactsReader,
} from "./handStarted.ts";

/** U78 (api): a hand-started contact's row; every booking field is null. */
const handStarted = {
  id: "rc-9",
  kind: "contact",
  booked: false,
  realized_contact_id: "rc-9",
  reservation_id: null,
  scheduled_contact_id: null,
  state: "stopped",
  starts_at: "2026-11-14T02:59:40Z",
  ends_at: "2026-11-14T03:08:52Z",
  spacecraft: { id: "sc-312", name: "EARENDIL-312", scid: 312 },
  station: { ref: "SVL", id: "gs-svl", code: "SVB", name: "Svalbard" },
  started_by: { kind: "user", id: "u-1", name: "Ada" },
  plan: null,
  source: null,
  pass_phase: null,
  delivery_state: null,
  releasable: false,
};
const booked = {
  id: "res-1",
  kind: "contact",
  booked: true,
  scheduled_contact_id: "sc-1",
  state: "confirmed",
  pass_phase: "scheduled",
  delivery_state: "pending",
  spacecraft_id: "sc-312",
  spacecraft: { id: "sc-312", name: "EARENDIL-312", scid: 312 },
  station: { ref: "SVL", id: "gs-svl", code: "SVB", name: "Svalbard" },
  antenna: null,
  starts_at: "2026-11-14T04:00:00Z",
  ends_at: "2026-11-14T04:08:00Z",
  uplink_capable: null,
  source: { provider: "p", provider_name: "Simulator", synthetic: true },
  max_elevation_deg: null,
  plan: null,
};

describe("hand-started rows (U78)", () => {
  it("reads a booked:false row as a hand-started contact and a booked row as a pass", () => {
    const list = decode(passesWithContactsReader, {
      from: "2026-11-14T00:00:00Z",
      to: "2026-11-21T00:00:00Z",
      truncated: false,
      passes: [handStarted, booked, { ...booked, id: "res-2", booked: undefined }],
    });
    if (!list.ok) throw new Error(list.error.message);
    expect(list.value.passes.map(isHandStarted)).toEqual([true, false, false]);
    const [first, second] = list.value.passes;
    if (!first || !isHandStarted(first)) throw new Error("expected a hand-started row");
    expect(first.state).toBe("stopped");
    expect(first.started_by?.kind).toBe("user");
    expect(second && !isHandStarted(second) ? second.scheduled_contact_id : null).toBe("sc-1");
  });

  it("keeps an open contact's end null and rejects a hand-started row claiming booked:true", () => {
    expect(decode(passOrContactReader, { ...handStarted, ends_at: null }).ok).toBe(true);
    expect(decode(passOrContactReader, { ...handStarted, booked: true }).ok).toBe(false);
  });
});

describe("never went live (api not_started, ux U78)", () => {
  it("says Cadence closed it only when it never went live and has a close time", () => {
    const read = (raw: unknown) => {
      const r = decode(passOrContactReader, raw);
      if (!r.ok || !isHandStarted(r.value)) throw new Error("expected a hand-started row");
      return r.value;
    };
    const swept = read({ ...handStarted, not_started: true });
    expect(neverLiveLine(swept, "2026-11-16")).toBe(
      "Closed by Cadence at 11-14 03:08Z: it never went live.",
    );
    expect(neverLiveLine(swept, "2026-11-14")).toBe(
      "Closed by Cadence at 03:08Z: it never went live.",
    );
    expect(
      neverLiveLine(
        read({ ...handStarted, state: "defined", ends_at: null, not_started: true }),
        "2026-11-16",
      ),
    ).toBe(null);
    expect(neverLiveLine(read({ ...handStarted, not_started: false }), "2026-11-16")).toBe(null);
    expect(neverLiveLine(read(handStarted), "2026-11-16")).toBe(null);
  });
});

describe("Contact record alone (U78)", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("opens at once and says an unknown id has no record, without repeating it", async () => {
    vi.stubGlobal("fetch", () =>
      Promise.resolve(
        new Response(
          JSON.stringify({ error: { code: "contact_not_found", message: "Not found." } }),
          { status: 404 },
        ),
      ),
    );
    const w = mount(ContactRecordView, {
      props: { missionId: missionId("m-1"), contactId: "rc-404", alone: true },
    });
    await flushPromises();
    expect(w.find("details").exists()).toBe(false);
    expect(w.text()).toContain("No contact record with this id.");
    expect(w.text()).not.toContain("rc-404");
  });
});
