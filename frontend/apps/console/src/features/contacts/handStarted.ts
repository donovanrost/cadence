import type { MissionId } from "@/api/index.ts";
import { decoders as d, request, type ApiResult, type Decoded, type Reader } from "@/api/index.ts";
import { passReader, passSpacecraft, passStation, type Pass } from "./api.ts";

/**
 * U78 (api): a contact started by hand, with no reservation, as a `booked: false` row of
 * `GET /passes?include=hand_started` or of `GET /passes/:id` given its realized contact id. The
 * row's booking fields are all null, so only what the drawer and History show is read.
 */
export const handStartedReader = d.object({
  id: d.token,
  kind: d.literal("contact"),
  booked: d.literal(false),
  realized_contact_id: d.token,
  /** The contact's own word (not a reservation's): defined and stopped appear only here. */
  state: d.knownText(["defined", "active", "stopped", "completed"] as const),
  /** When it went live (realized_at if it never did). */
  starts_at: d.timestamp,
  /** Null while the contact is open. */
  ends_at: d.nullable(d.timestamp),
  /** Null when its endpoints map to no spacecraft or to several. */
  spacecraft: d.nullable(passSpacecraft),
  station: passStation,
  started_by: d.nullable(
    d.object({
      kind: d.knownText(["user", "service", "system"] as const),
      id: d.nullable(d.token),
      // free-text: a person's display name (users only)
      name: d.nullable(d.string),
    }),
  ),
});
export type HandStartedContact = Decoded<typeof handStartedReader>;

/** A row that may be a reservation's pass or a hand-started contact (U78), split on `booked`. */
export const passOrContactReader: Reader<Pass | HandStartedContact> = (value, path = "") =>
  typeof value === "object" && value !== null && "booked" in value && value.booked === false
    ? handStartedReader(value, path)
    : passReader(value, path);

export const isHandStarted = (row: Pass | HandStartedContact): row is HandStartedContact =>
  row.booked === false;

/** `GET /passes?include=hand_started` (U78): both kinds merged and cut to 500 by the server. */
export const passesWithContactsReader = d.object({
  from: d.timestamp,
  to: d.timestamp,
  truncated: d.boolean,
  passes: d.array(passOrContactReader, 500),
});

/** `GET /passes/:id` for any id ?contact= can carry: reservation, scheduled or realized (U78). */
export function fetchPassOrContact(
  missionId: MissionId,
  id: string,
  signal?: AbortSignal,
): Promise<ApiResult<Pass | HandStartedContact>> {
  return request(
    `/missions/${encodeURIComponent(missionId)}/passes/${encodeURIComponent(id)}`,
    passOrContactReader,
    signal ? { signal } : {},
  );
}
