import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { spacecraftRow } from "@/features/fleet/index.ts";
import BookPassSheet from "./BookPassSheet.vue";
import {
  confirmLine,
  expiryWords,
  offerBlocked,
  offPlanLine,
  outcomeWords,
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
  station: { id: "sva", code: "SVA", name: "Svalbard" },
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
  reason_message: null,
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
        spacecraft: { id: "sc", name: "EARENDIL-312" },
        station_code: "KIR",
        starts_at: "2026-11-13T03:00:00Z",
        reason: "same_spacecraft",
      },
    });
    expect(offerBlocked(overlap, now)).toBe("Overlaps EARENDIL-312's KIR 03:00Z pass.");
  });

  it("says each outcome", () => {
    expect(outcomeWords(reserve({ provider_reference: "NL-48213" }), offer("a")).text).toBe(
      "Booked. Northlight confirmed SVA 03:10Z (ref NL-48213).",
    );
    expect(outcomeWords(reserve({ outcome: "requested" }), offer("a")).text).toBe(
      "Requested. Waiting for Northlight to confirm.",
    );
    expect(
      outcomeWords(reserve({ outcome: "rejected", reason_message: "no antenna free" }), offer("a")),
    ).toEqual({
      tone: "crit",
      text: "Northlight rejected it: no antenna free.",
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
      props: { missionId: "m", fleet: [spacecraftRow(1)], stations: [] },
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
    const [, init] = (fetch.mock.calls[1] ?? []) as [unknown, RequestInit | undefined];
    const sent: unknown = typeof init?.body === "string" ? JSON.parse(init.body) : null;
    expect(sent).toEqual({ token: "tok-a", note: "Gap after LOS" });
    expect(w.text()).toContain("Requested. Waiting for Northlight to confirm.");
    w.unmount();
    vi.useRealTimers();
  });
});
