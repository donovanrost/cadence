import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId as missionIdReader, spacecraftId, stationId, decode } from "@/api/index.ts";
import { spacecraftRow } from "@/features/fleet/index.ts";
import BookPassSheet from "./BookPassSheet.vue";
import {
  confirmLine,
  expiryWords,
  offerBlocked,
  offPlanLine,
  outcomeWords,
  stationWords,
  reserveReader,
  searchReader,
  type Offer,
  type Reserve,
} from "./singleBookings.ts";

/** Fixtures in plans/single-bookings.md's shapes (cd842bb2, agreed by api). */
const offer = (id: string, over: Partial<Offer> = {}): Offer => ({
  id,
  token: `tok-${id}`,
  expires_at: "2026-11-13T03:14:32Z",
  starts_at: "2026-11-13T03:10:00Z",
  ends_at: "2026-11-13T03:19:12Z",
  station: { ref: "sva", id: stationId("sva"), code: "SVA", name: "Svalbard" },
  antenna: null,
  provider: { id: "nl", name: "Northlight" },
  availability: "available",
  uplink_capable: true,
  synthetic: false,
  cost: null,
  overlaps: null,
  ...over,
});
const now = new Date("2026-11-13T03:00:00Z");
const reserve = (over: Partial<Reserve>): Reserve => ({
  outcome: "confirmed",
  reason: null,
  reservation_id: "res-1",
  provider_reference: null,
  pass: null,
  ...over,
});

describe("Book a pass words (ux Contacts.md § Book a pass)", () => {
  it("confirms, counts down, and says why an offer can't be chosen", () => {
    expect(confirmLine("EARENDIL-312", offer("a"), "uplink")).toBe(
      "Book EARENDIL-312 · SVA 03:10Z–03:19Z with Northlight, with an uplink.",
    );
    expect(expiryWords(offer("a"), now)).toEqual({ text: "Expires T−14:32", soon: false });
    expect(expiryWords(offer("a"), new Date("2026-11-13T03:13:00Z")).soon).toBe(true);
    expect(offerBlocked(offer("a"), new Date("2026-11-13T03:15:00Z"))).toBe(
      "Offer expired. Search again.",
    );
    const overlap = offer("b", {
      overlaps: {
        reservation_id: "r",
        spacecraft: { id: spacecraftId("sc"), name: "EARENDIL-312", scid: null },
        station_code: "KIR",
        starts_at: "2026-11-13T03:00:00Z",
        reason: "same_spacecraft",
      },
    });
    expect(offerBlocked(overlap, now)).toBe("Overlaps EARENDIL-312's KIR 03:00Z pass.");
    // No name (fe-setup, #190): the searched craft's own pass, another craft's, or just booked.
    const nameless = (reason: "same_spacecraft" | "same_antenna" | "unrecognized") => {
      const ov = overlap.overlaps;
      if (!ov) throw new Error("fixture");
      return {
        ...overlap,
        overlaps: { ...ov, spacecraft: { ...ov.spacecraft, name: null }, reason },
      };
    };
    expect(offerBlocked(nameless("same_spacecraft"), now)).toBe(
      "Overlaps this spacecraft's KIR 03:00Z pass.",
    );
    expect(offerBlocked(nameless("same_antenna"), now)).toBe(
      "Overlaps another spacecraft's KIR 03:00Z pass.",
    );
    expect(offerBlocked(nameless("unrecognized"), now)).toBe("Overlaps a booked KIR 03:00Z pass.");
  });

  it("says each outcome", () => {
    expect(outcomeWords(reserve({ provider_reference: "NL-48213" }), offer("a")).text).toBe(
      "Booked. Northlight confirmed SVA 03:10Z (ref NL-48213).",
    );
    expect(outcomeWords(reserve({ outcome: "requested" }), offer("a")).text).toBe(
      "Requested. Waiting for Northlight to confirm.",
    );
    expect(
      outcomeWords(reserve({ outcome: "rejected", reason: "no_capacity" }), offer("a")),
    ).toEqual({
      tone: "crit",
      text: "Northlight rejected it: the station has no capacity then.",
    });
    expect(
      offPlanLine(
        {
          booked_by: { name: "Mira K." },
          booked_at: "2026-11-13T02:10:00Z",
          note: "Gap after LOS",
        },
        now,
      ),
    ).toBe(
      "Booked outside a plan by Mira K. at 02:10Z: “Gap after LOS” · doesn't count toward contact rules.",
    );
    expect(offPlanLine(null, now)).toBeNull();
  });
});

describe("BookPassSheet", () => {
  afterEach(() => vi.unstubAllGlobals());
  const reply = (body: unknown) =>
    new Response(JSON.stringify({ data: body }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });

  it("searches, picks an offer, books it by token with the note", async () => {
    vi.useFakeTimers({ now, toFake: ["Date"] });
    const fetch = vi.fn();
    // A16b: opening reads the spacecraft's routes and the reach first.
    fetch.mockResolvedValueOnce(
      reply({
        spacecraft: { id: "sc-1", name: "EARENDIL-001" },
        routes: [],
        not_ready: [],
        limits: {
          max_window_s: 604_800,
          max_reach_s: 1_209_600,
          reach_until: "2026-11-27T03:00:00Z",
        },
      }),
    );
    fetch.mockResolvedValueOnce(
      reply({
        spacecraft: { id: "sc-1", name: "EARENDIL-001", scid: 1 },
        window: { from: "2026-11-13T03:00:00Z", to: "2026-11-14T03:00:00Z" },
        offers: [offer("a")],
        hidden: { no_uplink_route: 2 },
        not_ready: [],
        truncated: false,
      }),
    );
    fetch.mockResolvedValueOnce(reply(reserve({ outcome: "requested" })));
    vi.stubGlobal("fetch", fetch);
    const w = mount(BookPassSheet, {
      props: { missionId: missionIdReader("m"), fleet: [spacecraftRow(1)] },
      attachTo: document.body,
    });
    // oxlint-disable-next-line typescript/no-unsafe-call, typescript/no-unsafe-member-access -- vue-tsc checks the exposed open(); the lint type service can't resolve SFC instances.
    w.vm.open({ spacecraftId: spacecraftRow(1).id });
    await flushPromises();
    await w
      .findAll("button")
      .find((b) => b.text() === "Search")
      ?.trigger("click");
    await flushPromises();
    expect(w.text()).toContain("2 stations hidden: no uplink route to EARENDIL-001.");
    await w
      .get('button[aria-pressed="false"].w-full, ul[aria-label="Offers"] button')
      .trigger("click");
    await w.get("textarea").setValue("Gap after LOS");
    await w
      .findAll("button")
      .find((b) => b.text() === "Book this pass")
      ?.trigger("click");
    await flushPromises();
    const [, init] = (fetch.mock.calls[2] ?? []) as [unknown, RequestInit | undefined];
    const sent: unknown = typeof init?.body === "string" ? JSON.parse(init.body) : null;
    expect(sent).toEqual({ token: "tok-a", note: "Gap after LOS" });
    expect(w.text()).toContain("Requested. Waiting for Northlight to confirm.");
    w.unmount();
    vi.useRealTimers();
  });
});

describe("L15 replies as api 1ef9e85ef sends them", () => {
  it("reads an offer with a provider cost object, no antenna label and availability unavailable", () => {
    const raw = {
      spacecraft: { id: "sc-1", name: "EARENDIL-001", scid: 1 },
      window: { from: "2026-11-13T03:00:00Z", to: "2026-11-13T09:00:00Z" },
      offers: [
        {
          id: "o-1",
          token: "signed",
          expires_at: "2026-11-13T03:15:00Z",
          starts_at: "2026-11-13T04:00:00Z",
          ends_at: "2026-11-13T04:09:00Z",
          station: { ref: "prov-svb", id: null, code: null, name: null },
          antenna: { id: "ant-1", label: null },
          provider: { id: "northlight", name: "Northlight" },
          availability: "unavailable",
          uplink_capable: false,
          synthetic: false,
          cost: { amount: 12, currency: "EUR" },
          overlaps: null,
        },
      ],
      hidden: { no_uplink_route: 0 },
      not_ready: [{ code: "search_unavailable", message: "Kestrel didn't answer the search." }],
      truncated: false,
    };
    const r = decode(searchReader, raw);
    expect(r.ok && r.value.offers[0]?.cost).toBeNull();
    expect(r.ok && r.value.offers[0]?.availability).toBe("unavailable");
  });
  it("reads a booking reply without reason_message", () => {
    const r = decode(reserveReader, {
      outcome: "requested",
      reason: null,
      reservation_id: "res-9",
      provider_reference: null,
      pass: null,
    });
    expect(r.ok && r.value.reservation_id).toBe("res-9");
  });
});

describe("offer row (ux U69 A16a)", () => {
  const now = new Date("2026-11-13T03:05:00Z");
  it("names the antenna after the station, as given", () => {
    expect(stationWords(offer("a"))).toBe("SVA Svalbard");
    expect(stationWords(offer("a", { antenna: { id: "sg2", label: "Antenna SG2" } }))).toBe(
      "SVA Svalbard · Antenna SG2",
    );
    expect(stationWords(offer("a", { antenna: { id: "sg2", label: null } }))).toBe("SVA Svalbard");
  });
  it("blocks an unavailable window with the provider's word", () => {
    expect(offerBlocked(offer("a", { availability: "unavailable" }), now)).toBe(
      "Northlight reports this window as unavailable.",
    );
    expect(offerBlocked(offer("a", { availability: "limited" }), now)).toBeNull();
  });
});
