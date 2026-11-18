import type { MissionId } from "@/api/index.ts";
import type { RouteLocationRaw } from "vue-router";
import {
  decoders as d,
  detailsOf,
  isError,
  isKnown,
  knownText,
  request,
  spacecraftRef,
  stationRef,
  type ApiError,
  type Decoded,
  type StationId,
  type StationRef,
  type Unrecognized,
} from "@/api/index.ts";
import type { OpState } from "@/ui";

/**
 * Uplink readiness per pass (ux U33, DECISIONS #58; contacts.md §Uplink readiness). Quiet when
 * ready; a blocked pass says why in words, never the key. No imports from other features, so Now,
 * Contacts and Commands can all read it.
 */

export const readinessStates = ["ready", "qualifying", "recovering", "blocked"] as const;
/** Typing §12: a state this console doesn't know reads "unrecognized" and shows nothing. */
export type ReadinessState = (typeof readinessStates)[number] | "unrecognized";
const readinessState = d.known(readinessStates);

/**
 * The reasons the console words (U33 amendments, domain e683b3e2 / c7c79063 / a258d4fe). The
 * domain adds reasons, so this is knownText: an unknown one keeps its raw key for the fallback
 * sentence ("<provider> returned an error (Key words)") and Technical details.
 */
export const readinessReasons = [
  "cop1_awaiting_clcw",
  "cop1_clcw_stale",
  "session_not_attached",
  "protocol_state_restore_required",
  "uplink_farm_locked_out",
  "provider_cannot_attest_uplink_sessions",
  "provider_attestation_required",
  "malformed_provider_attestation",
  "provider_credential_unavailable",
  "transport_runtime_unavailable",
  "cop1_no_clcw_report",
  "uplink_state_unavailable",
  "unverified_peer_connected",
  // U46 (domain's release gate, api b9a60f096): an accepted provider change took the uplink leg out.
  "uplink_leg_dropped",
] as const;
type KnownReason = (typeof readinessReasons)[number];
export type ReadinessReason = KnownReason | Unrecognized;
const readinessReason = knownText(readinessReasons);
/** The reason's key as the server sent it (Technical details). */
export const reasonKey = (r: ReadinessReason) => (isKnown(r) ? r : r.unrecognized);

/** On pass rows: null when the pass has no uplink to be ready (downlink-only, not booked). */
export const passReadinessReader = d.object({
  state: readinessState,
  reason: d.nullable(readinessReason),
  since: d.nullable(d.timestamp),
  /** A number only when blocked (>0 crit, 0 caution); null otherwise (22300c64). */
  command_groups_queued: d.optional(d.nullable(d.integer)),
});
export type PassReadiness = Decoded<typeof passReadinessReader>;

export const starterKinds = ["user", "service", "system"] as const;
/** U46 (api): who started the contact, and the groups a named release on it would send. */
const contactFields = {
  /** null before the pass starts. */
  realized_contact_id: d.optional(d.nullable(d.token)),
  started_by: d.optional(
    d.nullable(
      d.object({
        kind: d.known(starterKinds),
        id: d.nullable(d.token),
        // free-text: a person's or service's display name
        name: d.nullable(d.string),
      }),
    ),
  ),
  started_at: d.optional(d.nullable(d.timestamp)),
  /** This mission's queued groups with unreleased members for that spacecraft, oldest first. */
  armed_group_ids: d.optional(d.array(d.token, 1_000)),
};
const passRef = d.object({
  reservation_id: d.token,
  contact_id: d.nullable(d.token),
  station: stationRef,
  starts_at: d.timestamp,
  ends_at: d.optional(d.timestamp),
  booked: d.optional(d.boolean),
  ...contactFields,
});
/** U46: a live hand-started contact that isn't a booked pass; ends_at null if open-ended. */
const handContact = d.object({
  realized_contact_id: d.token,
  booked: d.boolean,
  station: stationRef,
  starts_at: d.nullable(d.timestamp),
  ends_at: d.nullable(d.timestamp),
  started_by: contactFields.started_by,
  started_at: contactFields.started_at,
  armed_group_ids: d.array(d.token, 1_000),
});
export type HandContact = Decoded<typeof handContact>;

/**
 * On command groups: the pass the group is queued for, and its readiness. U46 (api): null pass
 * only while a hand-started contact is live and nothing booked lies ahead (`contact` is then set).
 */
export const groupUplinkReader = d.object({
  /**
   * U46 (api): the group's first target, whom the whole block describes (domain keys a group by
   * it). name falls back to the id for a deleted spacecraft. Optional until api's build lands.
   */
  spacecraft: d.optional(spacecraftRef),
  pass: d.nullable(passRef),
  /** 12792cb2: the next ready pass it would go on; named only when present. */
  next_pass: d.optional(d.nullable(passRef)),
  /** null when the spacecraft has no live pass: `pass` is then its next commandable pass. */
  readiness: d.nullable(
    d.object({
      state: readinessState,
      reason: d.nullable(readinessReason),
      since: d.nullable(d.timestamp),
    }),
  ),
  contact: d.optional(d.nullable(handContact)),
});
export type GroupUplink = Decoded<typeof groupUplinkReader>;

/** On attention items of source uplink_blocked. */
export const attentionUplinkReader = d.object({
  state: readinessState,
  reason: d.nullable(readinessReason),
  since: d.nullable(d.timestamp),
  command_group_ids: d.array(d.token, 1_000),
});

/**
 * Reason words (U33 amendment 2, domain e683b3e2): the clause after "Can't command:" or "Uplink
 * qualifying ·", lower-case, no final stop. The provider is named client-side; the raw key goes
 * only in the drawer's Technical details.
 */
export type ReasonContext = Readonly<{ provider?: string | null; los?: string | null }>;

const hhmm = (iso: string) => `${iso.slice(11, 16)}Z`;
const sentenceCase = (key: string) => {
  const w = key.replaceAll("_", " ").trim();
  return w.charAt(0).toUpperCase() + w.slice(1);
};

/** Not blocked: these read as "Uplink qualifying…", with no queue row. */
type Words = (c: ReasonContext, p: string) => string;
const QUALIFYING: Readonly<Partial<Record<KnownReason, Words>>> = {
  cop1_awaiting_clcw: () => "waiting for the spacecraft's first link report",
  // a5004aa8 / ux d85b7c3c
  cop1_clcw_stale: () => "the spacecraft's link reports stopped; waiting for them to resume",
  session_not_attached: (_c, p) => `waiting for ${p}'s uplink connection`,
};

const RESTART: KnownReason = "protocol_state_restore_required";
const CANNOT_ATTEST: KnownReason = "provider_cannot_attest_uplink_sessions";
/** domain c7c79063: only the spacecraft's report (or a new connection) clears it; Recover can't. */
const NO_CLCW: KnownReason = "cop1_no_clcw_report";
/** U46: the provider won't carry uplink on this pass; nothing on Cadence's side clears it. */
const DROPPED: KnownReason = "uplink_leg_dropped";

/** ux U46: "Northlight dropped the uplink from this pass at 02:40Z, so commands can't be sent on it." */
export function droppedLine(since: string | null, provider: string | null | undefined): string {
  return `${provider ?? "The provider"} dropped the uplink from this pass${since ? ` at ${hhmm(since)}` : ""}, so commands can't be sent on it.`;
}

const BLOCKED: Readonly<Partial<Record<KnownReason, Words>>> = {
  [RESTART]: (c) =>
    `the uplink restarted after this pass had sent commands, and it can't resume${c.los ? ` before LOS ${hhmm(c.los)}` : ""}`,
  uplink_farm_locked_out: () => "the spacecraft's receiver reports a lockout",
  [CANNOT_ATTEST]: (_c, p) =>
    `${p} can't vouch for uplink sessions, so Cadence won't command through it`,
  provider_attestation_required: (_c, p) => `${p} didn't vouch for this session`,
  malformed_provider_attestation: (_c, p) => `${p}'s proof for this session couldn't be read`,
  provider_credential_unavailable: (_c, p) => `Cadence couldn't read the credential for ${p}`,
  transport_runtime_unavailable: () => "the uplink transport isn't running",
  [NO_CLCW]: () => "the spacecraft didn't send a link report within 15 s of the uplink connecting",
  uplink_state_unavailable: () => "Cadence can't read the uplink's state right now",
  // #67 (domain a258d4fe; ux 000086ae): recoverable, like attestation_*.
  [DROPPED]: (_c, p) => `${p} dropped the uplink from this pass`,
  unverified_peer_connected: (_c, p) =>
    `an unverified connection took the uplink, so Cadence dropped it and is waiting for ${p}'s verified one`,
};

/** The clause for a key, in context. Unknown keys: "<provider> returned an error (Key words)". */
export function reasonClause(reason: ReadinessReason | null, c: ReasonContext = {}): string {
  const p = c.provider ?? "the provider";
  if (reason === null) return "the uplink isn't ready";
  if (isKnown(reason)) {
    const known = QUALIFYING[reason] ?? BLOCKED[reason];
    if (known) return known(c, p);
  }
  const key = reasonKey(reason);
  if (key.startsWith("attestation_")) return `${p}'s proof for this session didn't check out`;
  return `${p} returned an error (${sentenceCase(key)})`;
}

/** Sentence form (capitalized, no final stop), e.g. for Now's evidence line. */
export function reasonSentence(reason: ReadinessReason | null, c: ReasonContext = {}): string {
  const s = reasonClause(reason, c);
  return s.charAt(0).toUpperCase() + s.slice(1);
}

/**
 * #59 / f57e5fff: Recover re-runs qualification only. A restart after commands were sent, and a
 * provider that can't attest uplink sessions, can't be recovered on this pass.
 */
export const recoverable = (reason: ReadinessReason | null) =>
  reason !== RESTART && reason !== CANNOT_ATTEST && reason !== NO_CLCW && reason !== DROPPED;

/** What shows in Recover's place when it can't help (ux d6ba032b); U46's drop line says it already. */
export const noRecoverText = (reason: ReadinessReason | null): string | null =>
  reason === DROPPED
    ? null
    : reason === NO_CLCW
      ? "Recovery won't help: it clears when the spacecraft reports."
      : "Recovery isn't possible on this pass.";

/** Where to fix a reason, when it names one. */
export function reasonLink(
  reason: ReadinessReason | null,
): { label: string; to: RouteLocationRaw } | null {
  if (reason === "provider_credential_unavailable")
    return { label: "Org › Provider accounts", to: { name: "org.provider-accounts" } };
  if (reason === CANNOT_ATTEST)
    return {
      label: "Choose a provider that can in Setup › Ground stations.",
      to: { name: "setup.stations" },
    };
  return null;
}

/** What the stations index knows of a station (U33): its code and provider name. */
export type StationInfo = Readonly<{ code: string | null; provider: string | null }>;
/**
 * The stations index, with its two identifier spaces kept apart (§12C, audit §1.2 item 6):
 * `byId` takes the station's own id; `byRef` a provider's ground_station_ref, matched as text
 * against station ids and then codes, since a contact may name only its code.
 */
export type StationLookup = Readonly<{
  byId: (id: StationId | null | undefined) => StationInfo | null;
  byRef: (ref: string | null | undefined) => StationInfo | null;
}>;
const NO_STATIONS: StationLookup = { byId: () => null, byRef: () => null };
const codeFor = (st: StationRef, s: StationLookup) =>
  st.code ?? s.byId(st.id)?.code ?? s.byRef(st.ref)?.code ?? null;
const providerFor = (st: StationRef, s: StationLookup) =>
  s.byId(st.id)?.provider ?? s.byRef(st.ref)?.provider ?? null;

export type ReadinessTag = Readonly<{ state: OpState; label: string; sentence: string | null }>;

/**
 * The pass's readiness tag (U33). `where: "drawer"` also says "Uplink ready"; bars and rows stay
 * quiet when ready. States are ready | qualifying | blocked (amendment 2; an older "recovering"
 * reads as qualifying). null readiness (no live uplink session) shows nothing.
 */
export function readinessTag(
  r: Readonly<{ state: ReadinessState; reason: ReadinessReason | null; since: string | null }> & {
    command_groups_queued?: number | null | undefined;
  },
  where: "drawer" | "row",
  c: ReasonContext = {},
): ReadinessTag | null {
  const qualifying =
    r.state === "qualifying" ||
    r.state === "recovering" ||
    (r.reason !== null && isKnown(r.reason) && QUALIFYING[r.reason] !== undefined);
  if (qualifying) {
    // The server's state sets the tone (ux d85b7c3c); any reason it gives is worded.
    const why = r.reason !== null ? reasonSentence(r.reason, c) : null;
    const since = r.since ? `Qualifying since ${hhmm(r.since)}` : null;
    return {
      state: "neutral",
      label: "Uplink qualifying…",
      sentence: why ? `${why}.` : since ? `${since}.` : null,
    };
  }
  if (r.state === "ready")
    return where === "drawer" ? { state: "nominal", label: "Uplink ready", sentence: null } : null;
  if (r.state !== "blocked") return null;
  const state = (r.command_groups_queued ?? 1) > 0 ? "crit" : "caution";
  // U46: crit when groups are queued for it, else caution.
  if (r.reason === DROPPED)
    return { state, label: "Uplink dropped", sentence: droppedLine(r.since, c.provider) };
  const tail =
    r.reason === RESTART
      ? " The next pass isn't affected."
      : r.reason === NO_CLCW
        ? " It clears when the spacecraft reports or the link reconnects."
        : "";
  return {
    state,
    label: "Can't command",
    sentence: `Can't command: ${reasonClause(r.reason, c)}.${tail}`,
  };
}

/**
 * A command group's line when its pass is blocked (U33 amendment 2): "Can't command on the SVB-1
 * pass (AOS 00:54Z): <reason>. Nothing will be sent on this pass until the uplink recovers.
 * Otherwise it goes on the next pass (KIR 02:31Z) unless it expires at 03:00Z." The next pass is
 * booked, not promised ready; with none booked: "No later pass is booked for it yet."
 */
type PassAt = Readonly<{ station: StationRef; starts_at: string }>;
/** What the line reads of a group's uplink block (Investigate's lane passes its own pass). */
export type BlockedUplink = Readonly<{
  pass: PassAt | null;
  next_pass?: PassAt | null | undefined;
  readiness: GroupUplink["readiness"];
}>;

export function groupBlockedLine(
  uplink: BlockedUplink | null | undefined,
  expiresAt: string | null,
  stations: StationLookup = NO_STATIONS,
): string | null {
  const readiness = uplink?.readiness ?? null;
  if (!uplink?.pass || readiness?.state !== "blocked") return null;
  const station = codeFor(uplink.pass.station, stations) ?? uplink.pass.station.name ?? "its";
  const provider = providerFor(uplink.pass.station, stations);
  const next = uplink.next_pass ?? null;
  const fixable = recoverable(readiness.reason);
  const head = `Can't command on the ${station} pass (AOS ${hhmm(uplink.pass.starts_at)}): ${reasonClause(readiness.reason, { provider })}.`;
  const stop = fixable
    ? "Nothing will be sent on this pass until the uplink recovers."
    : "Nothing will be sent on this pass.";
  if (!next) return `${head} ${stop} No later pass is booked for it yet.`;
  const code = codeFor(next.station, stations);
  const onward = code
    ? `the next pass (${code} ${hhmm(next.starts_at)})`
    : `the next pass at ${hhmm(next.starts_at)}`;
  const expiry = expiresAt ? ` unless it expires at ${hhmm(expiresAt)}` : "";
  return `${head} ${stop} ${fixable ? "Otherwise it goes" : "It goes"} on ${onward}${expiry}.`;
}

const recovered = d.object({ state: readinessState, ready_at: d.nullable(d.timestamp) });
const refusal = d.object({ reason: d.optional(d.nullable(readinessReason)) });

export type RecoverOutcome = Readonly<{ tone: "nominal" | "info" | "caution"; text: string }>;

/** `Recover uplink` (U33): re-runs the automatic recovery; audited and safe to repeat, so no confirm. */
export async function recoverUplink(missionId: MissionId, passId: string): Promise<RecoverOutcome> {
  const r = await request(
    `/missions/${encodeURIComponent(missionId)}/passes/${encodeURIComponent(passId)}/recover-uplink`,
    recovered,
    { method: "POST" },
  );
  if (r.ok)
    return r.value.state === "ready"
      ? {
          tone: "nominal",
          text: `Uplink recovered${r.value.ready_at ? ` · ready at ${hhmm(r.value.ready_at)}` : ""}.`,
        }
      : { tone: "info", text: "Qualifying now." };
  return recoverErrorWords(r.error);
}

export function recoverErrorWords(e: ApiError): RecoverOutcome {
  if (isError(e, "uplink_recovery_refused")) {
    const reason = detailsOf(e, refusal)?.reason ?? null;
    return {
      tone: "caution",
      text: `Recovery refused: ${reason ? reasonClause(reason) : "no reason given"}.`,
    };
  }
  if (isError(e, "uplink_not_blocked"))
    return { tone: "info", text: "The uplink isn't blocked any more." };
  if (isError(e, "uplink_recovering")) return { tone: "info", text: "Qualifying now." };
  if (e.kind === "forbidden")
    return { tone: "caution", text: "Operators with mission access can recover the uplink." };
  if (e.kind === "unavailable" || e.kind === "malformed")
    return {
      tone: "caution",
      text: "No answer from the server, so recovery may or may not have started. Reload the pass to check.",
    };
  const message = "message" in e ? e.message : "the server didn't say why";
  return { tone: "caution", text: `Nothing changed: ${message.replace(/[.!?]+$/, "")}.` };
}
