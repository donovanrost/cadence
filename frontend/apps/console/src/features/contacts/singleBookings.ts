import type { MissionId } from "@/api/index.ts";
import {
  decoders as d,
  request,
  spacecraftRef,
  stationRef,
  type ApiResult,
  type Decoded,
  type Reader,
} from "@/api/index.ts";
import { formatHourMinute, formatShort } from "@/ui";
import { reasonWords } from "@/features/scheduling/booking-state.ts";
import { passReader } from "./api.ts";
import { listenerOverlapKey } from "./listenerOverlap.ts";
import { offerGeometry } from "@/features/scheduling/geometry.ts";

/**
 * §11 L15 single bookings outside a plan (proposal plans/single-bookings.md; ux Contacts.md § Book a
 * pass). Search over the spacecraft's ready routes, reserve one offer by its signed token
 * (idempotent), release through the pass's usual Release. Live since api 1ef9e85ef (qa's live
 * check 11-13); flip back to false to hide the entries.
 */
export const SINGLE_BOOKINGS_LIVE = true;

/** The provider's own cost, passed through (search.ex); anything but a number reads as unknown. */
const costReader: Reader<number | null> = (value) => (typeof value === "number" ? value : null);

const offerReader = d.object({
  id: d.token,
  token: d.string,
  expires_at: d.timestamp,
  starts_at: d.timestamp,
  ends_at: d.timestamp,
  // domain/api (L15): ref is always set; id, code and name are null for a provider station that
  // matches no Cadence station. §12 A5: the shared station reference.
  station: stationRef,
  antenna: d.nullable(d.object({ id: d.token, label: d.nullable(d.string) })),
  provider: d.object({ id: d.token, name: d.nullable(d.string) }),
  // GroundNetworks.Opportunity: available | limited | unavailable.
  availability: d.knownText(["available", "limited", "unavailable"] as const),
  uplink_capable: d.boolean,
  synthetic: d.boolean,
  cost: costReader,
  /** U58 (b), #361: booking it would overlap another pass on a one-connection listener (allowed). */
  listener_overlap: listenerOverlapKey,
  /** #892: predicted elevation and TCA, and whether no predicted pass backs the window. */
  ...offerGeometry,
  overlaps: d.nullable(
    d.object({
      reservation_id: d.token,
      spacecraft: spacecraftRef,
      // free-text: a station call sign, not a vocabulary
      station_code: d.nullable(d.string),
      starts_at: d.timestamp,
      reason: d.known(["same_spacecraft", "same_antenna"] as const),
    }),
  ),
});
export type Offer = Decoded<typeof offerReader>;

/**
 * A key per offer that survives a re-search (#970 review, a11y A5): tokens are signed afresh each
 * search, so rows keyed by them remount and focus drops to <body>. The window's station, provider,
 * start and end name it, with an ordinal for the same window offered on more than one route.
 */
export function offerKeys(offers: readonly Offer[]): readonly string[] {
  const seen = new Map<string, number>();
  return offers.map((o) => {
    const window = [o.station.ref, o.provider.id, o.starts_at, o.ends_at].join("|");
    const n = seen.get(window) ?? 0;
    seen.set(window, n + 1);
    return `${window}|${n}`;
  });
}

export const searchReader = d.object({
  spacecraft: spacecraftRef,
  window: d.object({ from: d.timestamp, to: d.timestamp }),
  offers: d.array(offerReader, 500),
  hidden: d.object({ no_uplink_route: d.integer }),
  not_ready: d.array(
    d.object({
      // free-text: the route finding's code is only a list key; the message is what's shown
      code: d.token,
      message: d.string,
    }),
    50,
  ),
  truncated: d.boolean,
});
export type Search = Decoded<typeof searchReader>;

export const reserveReader = d.object({
  outcome: d.oneOf(["confirmed", "requested", "unconfirmed", "rejected"] as const),
  // free-text: the provider's category or code, worded by K1's reasonWords (which has a fallback)
  reason: d.nullable(d.token),
  // api 1ef9e85ef: the reservation asked for (null only if the provider job hasn't written it).
  reservation_id: d.nullable(d.token),
  provider_reference: d.nullable(d.string),
  pass: d.nullable(passReader),
});
export type Reserve = Decoded<typeof reserveReader>;

export type SearchInput = Readonly<{
  spacecraftId: string;
  from: Date;
  to: Date;
  direction: "downlink" | "uplink";
  /** A16b: the chosen routes' keys; none = every ready route. */
  routeKeys: readonly string[];
}>;

const base = (missionId: MissionId) => `/missions/${encodeURIComponent(missionId)}/single-bookings`;

export function searchOffers(missionId: MissionId, input: SearchInput): Promise<ApiResult<Search>> {
  return request(`${base(missionId)}/search`, searchReader, {
    method: "POST",
    body: {
      spacecraft_id: input.spacecraftId,
      from: input.from.toISOString(),
      to: input.to.toISOString(),
      direction: input.direction,
      ...(input.routeKeys.length ? { route_keys: input.routeKeys } : {}),
    },
  });
}

export function reserveOffer(missionId: MissionId, token: string, note: string) {
  return request(base(missionId), reserveReader, {
    method: "POST",
    body: { token, ...(note.trim() ? { note: note.trim() } : {}) },
  });
}

const clock = (iso: string) => formatHourMinute(new Date(iso)).replace(/Z$/, "");
/** "SVA Svalbard · Northlight · 03:10Z–03:19Z" pieces (§4). */
/** ux U69 A16a: the station, then the antenna's label as given ('Svalbard · Antenna SG2'). */
export const stationWords = (o: Offer) => {
  const station = [o.station.code, o.station.name].filter(Boolean).join(" ") || "A station";
  return o.antenna?.label ? `${station} · ${o.antenna.label}` : station;
};
export const providerWords = (o: Offer) => o.provider.name ?? "the provider";
export const windowWords = (o: Offer) => `${clock(o.starts_at)}Z–${clock(o.ends_at)}Z`;

/**
 * An overlapped pass whose craft has no name (fe-setup, #190): same_spacecraft is the searched
 * craft's own pass; an unknown reason says only that a pass is booked.
 */
const NAMELESS_OWNER = {
  same_spacecraft: "this spacecraft's",
  same_antenna: "another spacecraft's",
  unrecognized: "a booked",
} as const;

/** Why an offer can't be chosen, or null: it overlaps a booked pass, or its token expired. */
export function offerBlocked(o: Offer, now: Date): string | null {
  if (Date.parse(o.expires_at) <= now.getTime()) return "Offer expired. Search again.";
  // ux U69 A16a: the provider's own word; booking it would only be refused.
  if (o.availability === "unavailable")
    return `${o.provider.name ?? "The provider"} reports this window as unavailable.`;
  const ov = o.overlaps;
  if (ov) {
    const owner = ov.spacecraft.name ? `${ov.spacecraft.name}'s` : NAMELESS_OWNER[ov.reason];
    return `Overlaps ${owner} ${ov.station_code ? `${ov.station_code} ` : ""}${formatHourMinute(new Date(ov.starts_at))} pass.`;
  }
  return null;
}

/** `EXPIRES T−14:32`; `soon` under 2 min (caution). */
export function expiryWords(o: Offer, now: Date): { text: string; soon: boolean } {
  const s = Math.max(0, Math.round((Date.parse(o.expires_at) - now.getTime()) / 1000));
  const text = `Expires T−${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
  return { text, soon: s < 120 };
}

/** "Book EARENDIL-312 · SVA 03:10Z–03:19Z with Northlight, with an uplink." */
export function confirmLine(
  spacecraft: string,
  o: Offer,
  direction: "downlink" | "uplink",
): string {
  const where = o.station.code ?? o.station.name ?? "the station";
  return `Book ${spacecraft} · ${where} ${windowWords(o)} with ${providerWords(o)}${direction === "uplink" ? ", with an uplink" : ""}.`;
}

/**
 * Outcome sentences (ux Contacts.md § Book a pass, Outcomes). `failed` (a11y B6, #243): the person
 * has something to act on (unconfirmed or rejected), so it's announced as an alert; else a status.
 */
export function outcomeWords(
  r: Reserve,
  o: Offer,
): Readonly<{ tone: "nominal" | "info" | "caution" | "crit"; text: string; failed: boolean }> {
  const who = providerWords(o);
  const where = `${o.station.code ?? o.station.name ?? "the station"} ${formatHourMinute(new Date(o.starts_at))}`;
  switch (r.outcome) {
    case "confirmed":
      return {
        tone: "nominal",
        failed: false,
        text: `Booked. ${who} confirmed ${where}${r.provider_reference ? ` (ref ${r.provider_reference})` : ""}.`,
      };
    case "requested":
      return { tone: "info", failed: false, text: `Requested. Waiting for ${who} to confirm.` };
    case "unconfirmed":
      return {
        tone: "caution",
        failed: true,
        text: `${who} didn't say whether it's booked. It's marked unconfirmed; resolve it on the pass.`,
      };
    case "rejected":
      return {
        tone: "crit",
        failed: true,
        text: `${who} rejected it: ${reasonWords(r.reason).text}.`,
      };
  }
}

/**
 * D2 (ux): "Booked outside a plan by Mira K. at 02:10Z: “note” · doesn't count toward contact
 * rules." Null for plan bookings.
 */
export function offPlanLine(
  offPlan:
    | Readonly<{
        booked_by: { name: string | null } | null;
        booked_at: string;
        note: string | null;
      }>
    | null
    | undefined,
  now: Date,
): string | null {
  if (!offPlan) return null;
  const iso = offPlan.booked_at;
  const today = iso.slice(0, 10) === now.toISOString().slice(0, 10);
  const when = `${today ? "" : `${iso.slice(5, 10)} `}${iso.slice(11, 16)}Z`;
  const by = offPlan.booked_by?.name ? ` by ${offPlan.booked_by.name}` : "";
  const note = offPlan.note ? `: “${offPlan.note}”` : "";
  return `Booked outside a plan${by} at ${when}${note} · doesn't count toward contact rules.`;
}

/** Empty search: "No passes for EARENDIL-312 between 03:00Z and 09:00Z." */
export function emptyWords(s: Search, via = ""): string {
  const at = (iso: string) => formatShort(new Date(iso));
  return `No passes for ${s.spacecraft.name ?? "this spacecraft"}${via} between ${at(s.window.from)} and ${at(s.window.to)}.`;
}
