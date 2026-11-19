import type { MissionId } from "@/api/index.ts";
import {
  decode,
  decoders as d,
  detailsOf,
  isError,
  isKnown,
  request,
  type ApiError,
  type ApiResult,
  type Decoded,
  type Reader,
} from "@/api/index.ts";
import { plural } from "@/ui";

/**
 * U46 named release (DECISIONS #84; api's shape 11-14): an operator sends the armed groups into one
 * live contact by naming it. Only hand-started contacts offer it (lead), and they confirm first
 * (ux's danger sheet). Codes are known-text: domain adds them, and an unknown one reads as words.
 */

/** A refusal's details as sent; each code's shape is read where it's worded. */
export const raw: Reader<unknown> = (value) => value;

export const groupRefusalCodes = [
  "command_group_not_found",
  "command_group_not_armed",
  "release_contact_not_target_spacecraft",
  "command_group_nothing_to_release",
] as const;
export const stopCodes = [
  "command_window_closed",
  "command_queue_entry_not_next_for_release",
  "earlier_command_failed",
  "command_release_refused",
  "release_basis_changed",
] as const;
export const releaseCode = d.knownText([...groupRefusalCodes, ...stopCodes]);
export type ReleaseCode = Decoded<typeof releaseCode>;

export const windowWhys = ["outside_pass", "uplink_leg_dropped"] as const;
/** command_window_closed's details: the contact's own times, so a gone contact still reads. */
const windowClosed = d.object({
  why: d.known(windowWhys),
  starts_at: d.optional(d.nullable(d.timestamp)),
  ends_at: d.optional(d.nullable(d.timestamp)),
});
// free-text: the server's fallback sentence for a code the console doesn't word
const messageDetails = d.object({ message: d.optional(d.nullable(d.string)) });

const outcomes = ["released", "stopped", "refused"] as const;
const resultReader = d.object({
  command_group_id: d.token,
  outcome: d.known(outcomes),
  released_entry_ids: d.array(d.token, 1_000),
  not_attempted_entry_ids: d.array(d.token, 1_000),
  stopped: d.nullable(
    d.object({
      command_queue_entry_id: d.token,
      command_request_id: d.token,
      code: releaseCode,
      details: d.optional(d.nullable(raw)),
    }),
  ),
  refused: d.nullable(d.object({ code: releaseCode, details: d.optional(d.nullable(raw)) })),
});
export type ReleaseResult = Decoded<typeof resultReader>;
const releaseReader = d.object({
  realized_contact_id: d.token,
  booked: d.boolean,
  results: d.array(resultReader, 50),
});
export type Release = Decoded<typeof releaseReader>;

/** A member's latest named-release stop (null once a later release clears it). */
export const releaseRefusalReader = d.object({
  code: releaseCode,
  details: d.optional(d.nullable(raw)),
  at: d.timestamp,
  realized_contact_id: d.nullable(d.token),
  booked: d.nullable(d.boolean),
});
export type ReleaseRefusal = Decoded<typeof releaseRefusalReader>;

const hhmm = (iso: string) => `${iso.slice(11, 16)}Z`;
/** §4 short form: "03:10Z" today, "11-12 03:10Z" otherwise. */
const shortAt = (iso: string, now: Date) =>
  `${iso.slice(0, 10) === now.toISOString().slice(0, 10) ? "" : `${iso.slice(5, 10)} `}${hhmm(iso)}`;

export type WindowContext = Readonly<{
  /** The moment the window was judged: the refusal's `at`, or now for a whole-request 409. */
  at: Date;
  /** false for a hand-started contact: it reads "contact", not "pass". */
  booked?: boolean | null | undefined;
  provider?: string | null | undefined;
  /** The spacecraft the screen names (U25), for the per-spacecraft clauses. */
  spacecraft?: string | null | undefined;
}>;

/** ux U46 (b): why the command window was closed, as a clause after "Not released: ". */
export function windowClosedClause(details: unknown, c: WindowContext): string {
  const w = decode(windowClosed, details);
  if (!w.ok || w.value.why === "unrecognized") return "the command window is closed";
  const contact = c.booked === false;
  if (w.value.why === "uplink_leg_dropped")
    return `${c.provider ?? "the provider"} dropped the uplink from this ${contact ? "contact" : "pass"}`;
  const { starts_at: aos, ends_at: los } = w.value;
  const t = c.at.getTime();
  // ux: a hand-started contact has no AOS or LOS; a booked pass keeps them.
  if (aos && t < Date.parse(aos))
    return contact
      ? "the contact hasn't started"
      : `the pass hasn't started (AOS ${shortAt(aos, c.at)})`;
  if (los && t >= Date.parse(los))
    return contact
      ? `the contact ended at ${shortAt(los, c.at)}`
      : `the pass has ended (LOS ${shortAt(los, c.at)})`;
  if (contact && !los && w.value.why === "outside_pass") return "the contact has ended";
  return "the command window is closed";
}

/** ux's ruled clauses (e8d04f6b2); `sc` is the spacecraft's name, or "the contact's spacecraft". */
const CLAUSES: Readonly<
  Record<
    Exclude<(typeof groupRefusalCodes | typeof stopCodes)[number], "command_window_closed">,
    (sc: string) => string
  >
> = {
  command_group_not_found: () => "the request wasn't found",
  command_group_not_armed: () => "the request isn't queued for a contact",
  release_contact_not_target_spacecraft: (sc) => `it has no uplinks for ${sc}`,
  command_group_nothing_to_release: (sc) => `its uplinks to ${sc} have already gone or ended`,
  command_queue_entry_not_next_for_release: (sc) =>
    `an earlier queued uplink to ${sc} has to go first`,
  earlier_command_failed: () => "an earlier uplink in it failed",
  command_release_refused: () => "the uplink transport refused it",
  release_basis_changed: () => "the configuration it was approved against has changed",
};

/** One code's clause, lower-case and without a final stop; unknown codes use the server's message. */
export function releaseClause(code: ReleaseCode, details: unknown, c: WindowContext): string {
  if (code === "command_window_closed") return windowClosedClause(details, c);
  if (isKnown(code)) return CLAUSES[code](c.spacecraft ?? "the contact's spacecraft");
  const message = decode(messageDetails, details);
  const text = message.ok ? message.value.message : null;
  return text ? text.replace(/[.!?]+$/, "") : code.unrecognized.replaceAll("_", " ");
}

/** A member's line from its latest stop: "Not released: the pass has ended (LOS 03:19Z)." */
export function refusalLine(
  r: ReleaseRefusal,
  c: Omit<WindowContext, "at" | "booked"> = {},
): string {
  return `Not released: ${releaseClause(r.code, r.details, { ...c, at: new Date(r.at), booked: r.booked })}.`;
}

/** One group's outcome after a named release. */
export function resultLine(r: ReleaseResult, c: WindowContext): string {
  const sent = r.released_entry_ids.length;
  const left = r.not_attempted_entry_ids.length;
  if (r.outcome === "released") return `Released ${plural(sent, "uplink")}.`;
  const why = r.stopped ?? r.refused;
  const clause = why ? releaseClause(why.code, why.details, c) : "the server didn't say why";
  if (r.outcome === "stopped" && sent > 0)
    return `Released ${plural(sent, "uplink")}, then stopped: ${clause}.${left ? ` ${plural(left, "uplink")} still queued.` : ""}`;
  return `Not released: ${clause}.`;
}

export type ReleaseOutcome =
  | Readonly<{ kind: "done"; release: Release }>
  | Readonly<{ kind: "confirm" }>
  | Readonly<{ kind: "refused"; text: string }>;

/** Who may release (operate_mission, fresh human): the no-access line. */
export const NO_ACCESS_RELEASE = "Operators with mission access can release commands.";

const notReleasable = d.object({ state: d.knownText(["stopped", "completed"] as const) });

/** Whole-request refusals (nothing went out). `confirm` asks for ux's danger sheet. */
export function releaseErrorWords(e: ApiError, c: WindowContext): ReleaseOutcome {
  const no = (text: string): ReleaseOutcome => ({ kind: "refused", text });
  if (isError(e, "command_window_closed"))
    return no(`Not released: ${windowClosedClause("details" in e ? e.details : null, c)}.`);
  if (isError(e, "unbooked_contact_unconfirmed")) return { kind: "confirm" };
  if (isError(e, "realized_contact_not_found"))
    return no("Not released: the contact wasn't found.");
  if (isError(e, "realized_contact_not_releasable"))
    return no(
      detailsOf(e, notReleasable)
        ? "Not released: the contact has ended."
        : "Not released: the contact can't take releases now.",
    );
  if (e.kind === "forbidden") return no(NO_ACCESS_RELEASE);
  if (isError(e, "invalid_params"))
    return no("Not released: the server didn't accept the list of requests. Reload and try again.");
  if (e.kind === "unavailable" || e.kind === "malformed")
    return no("No answer from the server, so some uplinks may have gone. Reload to check.");
  const message = "message" in e ? e.message : "the server didn't say why";
  return no(`Not released: ${message.replace(/[.!?]+$/, "")}.`);
}

/** POST …/contacts/:realized_contact_id/release, groups in the order given (queue order). */
export async function releaseOnContact(
  missionId: MissionId,
  realizedContactId: string,
  groupIds: readonly string[],
  confirmUnbooked: boolean,
  c: WindowContext,
): Promise<ReleaseOutcome> {
  const r: ApiResult<Release> = await request(
    `/missions/${encodeURIComponent(missionId)}/contacts/${encodeURIComponent(realizedContactId)}/release`,
    releaseReader,
    {
      method: "POST",
      body: { command_group_ids: groupIds, confirm_unbooked: confirmUnbooked },
    },
  );
  return r.ok ? { kind: "done", release: r.value } : releaseErrorWords(r.error, c);
}

/** ux U46 (a): the command-window line from the pass times, not the snapshot. */
export function windowLine(startsAt: string, endsAt: string | null | undefined, now: Date) {
  if (now.getTime() < Date.parse(startsAt))
    return `Command window opens at AOS ${shortAt(startsAt, now)}.`;
  if (!endsAt) return null;
  return now.getTime() >= Date.parse(endsAt)
    ? `Command window closed at LOS ${shortAt(endsAt, now)}.`
    : `Command window open until LOS ${shortAt(endsAt, now)}.`;
}

/** ux U46 sheet body: "EARENDIL-001's contact at SVA, started by Mira K. at 00:12Z, wasn't …". */
export function unbookedSheetBody(
  spacecraft: string | null,
  station: string | null,
  startedBy: string | null,
  startedAt: string | null,
  groups: number,
  now: Date,
): string {
  const whose = spacecraft ? `${spacecraft}'s contact` : "This contact";
  const where = station ? ` at ${station}` : "";
  const by = startedBy
    ? `, started by ${startedBy}${startedAt ? ` at ${shortAt(startedAt, now)}` : ""},`
    : startedAt
      ? `, started at ${shortAt(startedAt, now)},`
      : "";
  return `${whose}${where}${by} wasn't booked as a pass. Release ${plural(groups, "request")} to it anyway?`;
}

/** What the request log needs to word a named release beyond the event (ux U46). */
export type ReleaseLogContext = Readonly<{
  /** "SVA 03:10Z" ("SVA 11-12 03:10Z" on another day, §4) for the booked pass with this id. */
  passLabel?: ((realizedContactId: string, at: Date) => string | null) | undefined;
  /** The contact's spacecraft, only when it's known to be that one (U25). */
  spacecraftOf?: ((realizedContactId: string | null) => string | null) | undefined;
}>;

type ContactRef = Readonly<{ realized_contact_id?: string | null | undefined }>;
type LabelSource = Readonly<{
  spacecraft?: Readonly<{ name: string | null }> | undefined;
  pass:
    | (ContactRef &
        Readonly<{
          station: Readonly<{ code: string | null; name: string | null }>;
          starts_at: string;
        }>)
    | null;
  contact?: ContactRef | null | undefined;
}>;

/**
 * The group's uplink block as log context. ux (U25): the spacecraft is named only when it's known
 * to be the contact's: the group's only target, or the block's own pass or contact (whose
 * spacecraft api names). Otherwise the clause says "the contact's spacecraft".
 */
export function releaseLogContext(
  uplink: LabelSource | null | undefined,
  onlyTarget: string | null,
): ReleaseLogContext {
  const pass = uplink?.pass ?? null;
  const ours = (id: string | null) =>
    id !== null &&
    (pass?.realized_contact_id === id || uplink?.contact?.realized_contact_id === id);
  return {
    spacecraftOf: (id) => onlyTarget ?? (ours(id) ? (uplink?.spacecraft?.name ?? null) : null),
    passLabel: (id, at) => {
      if (!pass || pass.realized_contact_id !== id) return null;
      const code = pass.station.code ?? pass.station.name;
      const when = shortAt(pass.starts_at, at);
      return code ? `${code} ${when}` : when;
    },
  };
}
