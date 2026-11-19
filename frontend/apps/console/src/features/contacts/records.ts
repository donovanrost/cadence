import type { MissionId } from "@/api/index.ts";
import { decoders as d, request, type ApiResult, type Decoded } from "@/api/index.ts";

/**
 * L14 (api A11/A13): a pass's reservation and contact records for the drawer's Technical details,
 * re-serving what the legacy reservation review and contact record pages read. Store and provider
 * words (states, audit actions, field names) are free text, shown as said.
 */
const idVersion = d.object({ id: d.token, version: d.nullable(d.integer) });

export const reservationReader = d.object({
  reservation: d.object({
    id: d.token,
    provider_revision: d.nullable(d.integer),
    // free-text: the reservation store's lifecycle word, shown in sentence case.
    lifecycle_state: d.string,
    provider: idVersion,
    transport: d.nullable(idVersion),
    plan: d.nullable(idVersion),
    requirement: d.nullable(idVersion),
    scheduled_contact_id: d.nullable(d.token),
    last_reconciled_at: d.nullable(d.timestamp),
  }),
  values: d.array(
    d.object({
      // free-text: the provider field's own name (ux U74: as given).
      field: d.string,
      requested_json: d.nullable(d.string),
      confirmed_json: d.nullable(d.string),
      accepted_json: d.nullable(d.string),
      restricted: d.boolean,
      /** api: requested, confirmed and accepted aren't all equal (withheld cells excluded). */
      differs: d.optional(d.boolean),
    }),
    50,
  ),
  audit: d.object({
    entries: d.array(
      d.object({
        id: d.token,
        // free-text: the provider audit's own short words.
        action: d.string,
        // free-text: as above.
        outcome: d.string,
        recorded_at: d.timestamp,
        change_id: d.nullable(d.token),
      }),
      25,
    ),
    next_cursor: d.nullable(d.token),
  }),
});
export type Reservation = Decoded<typeof reservationReader>;

export function fetchReservation(
  missionId: MissionId,
  passId: string,
  auditCursor: string | null = null,
  signal?: AbortSignal,
): Promise<ApiResult<Reservation>> {
  const q = auditCursor ? `?audit_cursor=${encodeURIComponent(auditCursor)}` : "";
  return request(
    `/missions/${encodeURIComponent(missionId)}/passes/${encodeURIComponent(passId)}/reservation${q}`,
    reservationReader,
    signal ? { signal } : {},
  );
}

const sides = (values: readonly string[]) => d.knownText(values);
export const contactRecordReader = d.object({
  subject: d.object({ id: d.token, kind: d.knownText(["scheduled", "realized"] as const) }),
  scheduled: d.nullable(
    d.object({
      id: d.token,
      current_revision: d.nullable(d.integer),
      // free-text: the contact store's lifecycle word.
      lifecycle_state: d.string,
      starts_at: d.nullable(d.timestamp),
      ends_at: d.nullable(d.timestamp),
      realized_id: d.nullable(d.token),
      // free-text: the provider's own contact reference.
      provider_contact_ref: d.nullable(d.string),
    }),
  ),
  realized: d.nullable(
    d.object({
      id: d.token,
      scheduled_id: d.nullable(d.token),
      // free-text: as above.
      lifecycle_state: d.string,
      // free-text: the realized contact's clock mode as the store names it.
      clock_mode: d.nullable(d.string),
      realized_at: d.nullable(d.timestamp),
      initial_time: d.nullable(d.timestamp),
    }),
  ),
  paths: d.array(
    d.object({
      side: sides(["scheduled", "realized"] as const),
      id: d.token,
      // free-text: path direction and selection as the store words them.
      direction: d.string,
      // free-text: as above.
      selection: d.string,
      source_endpoint_ref: d.nullable(d.string),
      // api 42e3b9550: a provider binding has an adapter key, not a family key.
      provider_bindings: d.array(d.object({ id: d.token, adapter_key: d.string }), 50),
      transport_bindings: d.array(
        d.object({ id: d.token, family_key: d.string, target_scope: d.string }),
        50,
      ),
    }),
    100,
  ),
  sources: d.array(
    d.object({ id: d.token, side: sides(["reviewed_schedule", "realized"] as const) }),
    200,
  ),
  intents: d.array(
    d.object({ id: d.token, side: sides(["current_schedule", "realized"] as const) }),
    200,
  ),
  revisions: d.object({
    entries: d.array(
      d.object({
        revision: d.integer,
        created_at: d.timestamp,
        created_by: d.nullable(
          d.object({
            kind: d.nullable(d.knownText(["user", "system"] as const)),
            id: d.nullable(d.string),
            name: d.nullable(d.string),
          }),
        ),
        provider_change_id: d.nullable(d.token),
        starts_at: d.nullable(d.timestamp),
        ends_at: d.nullable(d.timestamp),
        // free-text: as above.
        lifecycle_state: d.string,
      }),
      25,
    ),
    next_cursor: d.nullable(d.token),
  }),
  truncated: d.boolean,
});
export type ContactRecord = Decoded<typeof contactRecordReader>;

export function fetchContactRecord(
  missionId: MissionId,
  contactId: string,
  revisionsCursor: string | null = null,
  signal?: AbortSignal,
): Promise<ApiResult<ContactRecord>> {
  const q = revisionsCursor ? `?revisions_cursor=${encodeURIComponent(revisionsCursor)}` : "";
  return request(
    `/missions/${encodeURIComponent(missionId)}/contacts/${encodeURIComponent(contactId)}/record${q}`,
    contactRecordReader,
    signal ? { signal } : {},
  );
}
