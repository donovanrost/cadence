import { decoders as d, request, type ApiError, type Decoded } from "@/api/index.ts";
import type { OpState } from "@/ui";

/**
 * Uplink readiness per pass (ux U33, DECISIONS #58; contacts.md §Uplink readiness). Quiet when
 * ready; a blocked pass says why in words, never the key. No imports from other features, so Now,
 * Contacts and Commands can all read it.
 */

export const readinessStates = ["ready", "qualifying", "recovering", "blocked"] as const;
export type ReadinessState = (typeof readinessStates)[number];

/** On pass rows: null when the pass has no uplink to be ready (downlink-only, not booked). */
export const passReadinessReader = d.object({
  state: d.token,
  reason: d.nullable(d.token),
  since: d.nullable(d.timestamp),
  /** A number only when blocked (>0 crit, 0 caution); null otherwise (22300c64). */
  command_groups_queued: d.optional(d.nullable(d.integer)),
});
export type PassReadiness = Decoded<typeof passReadinessReader>;

const passRef = d.object({
  reservation_id: d.token,
  contact_id: d.nullable(d.token),
  station: d.object({
    ref: d.nullable(d.string),
    id: d.nullable(d.token),
    code: d.nullable(d.string),
    name: d.nullable(d.string),
  }),
  starts_at: d.timestamp,
});

/** On command groups: the pass the group is queued for, and its readiness. */
export const groupUplinkReader = d.object({
  pass: passRef,
  /** 12792cb2: the next ready pass it would go on; named only when present. */
  next_pass: d.optional(d.nullable(passRef)),
  /** null when the spacecraft has no live pass: `pass` is then its next commandable pass. */
  readiness: d.nullable(
    d.object({
      state: d.token,
      reason: d.nullable(d.token),
      since: d.nullable(d.timestamp),
    }),
  ),
});
export type GroupUplink = Decoded<typeof groupUplinkReader>;

/** On attention items of source uplink_blocked. */
export const attentionUplinkReader = d.object({
  state: d.token,
  reason: d.nullable(d.token),
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
const QUALIFYING: Readonly<Record<string, (c: ReasonContext, p: string) => string>> = {
  cop1_awaiting_clcw: () => "waiting for the spacecraft's first link report",
  // a5004aa8 / ux d85b7c3c
  cop1_clcw_stale: () => "the spacecraft's link reports stopped; waiting for them to resume",
  session_not_attached: (_c, p) => `waiting for ${p}'s uplink connection`,
};

const RESTART = "protocol_state_restore_required";
const CANNOT_ATTEST = "provider_cannot_attest_uplink_sessions";

const BLOCKED: Readonly<Record<string, (c: ReasonContext, p: string) => string>> = {
  [RESTART]: (c) =>
    `the uplink restarted after this pass had sent commands, and it can't resume${c.los ? ` before LOS ${hhmm(c.los)}` : ""}`,
  uplink_farm_locked_out: () => "the spacecraft's receiver reports a lockout",
  [CANNOT_ATTEST]: (_c, p) =>
    `${p} can't vouch for uplink sessions, so Cadence won't command through it`,
  provider_attestation_required: (_c, p) => `${p} didn't vouch for this session`,
  malformed_provider_attestation: (_c, p) => `${p}'s proof for this session couldn't be read`,
  provider_credential_unavailable: (_c, p) => `Cadence couldn't read the credential for ${p}`,
  transport_runtime_unavailable: () => "the uplink transport isn't running",
  cop1_no_clcw_report: () =>
    "the spacecraft didn't send a link report within 15 s of the uplink connecting",
  uplink_state_unavailable: () => "Cadence can't read the uplink's state right now",
  // #67 (domain a258d4fe; ux 000086ae): recoverable, like attestation_*.
  unverified_peer_connected: (_c, p) =>
    `an unverified connection took the uplink, so Cadence dropped it and is waiting for ${p}'s verified one`,
};

/** The clause for a key, in context. Unknown keys: "<provider> returned an error (Key words)". */
export function reasonClause(key: string | null, c: ReasonContext = {}): string {
  const p = c.provider ?? "the provider";
  if (key === null) return "the uplink isn't ready";
  const known = QUALIFYING[key] ?? BLOCKED[key];
  if (known) return known(c, p);
  if (key.startsWith("attestation_")) return `${p}'s proof for this session didn't check out`;
  return `${p} returned an error (${sentenceCase(key)})`;
}

/** Sentence form (capitalized, no final stop), e.g. for Now's evidence line. */
export function reasonSentence(key: string | null, c: ReasonContext = {}): string {
  const s = reasonClause(key, c);
  return s.charAt(0).toUpperCase() + s.slice(1);
}

/**
 * #59 / f57e5fff: Recover re-runs qualification only. A restart after commands were sent, and a
 * provider that can't attest uplink sessions, can't be recovered on this pass.
 */
export const recoverable = (reason: string | null) =>
  reason !== RESTART && reason !== CANNOT_ATTEST;

/** Where to fix a reason, when it names one. */
export function reasonLink(reason: string | null) {
  if (reason === "provider_credential_unavailable")
    return { label: "Org › Provider accounts", to: { name: "org.provider-accounts" } };
  if (reason === CANNOT_ATTEST)
    return {
      label: "Choose a provider that can in Setup › Ground stations.",
      to: { name: "setup.stations" },
    };
  return null;
}

/** The stations index by ref: code and provider name (U33). */
type ByRef = (ref: string | null | undefined) => string | null;
export type StationLookup = Readonly<{ code: ByRef; provider: ByRef }>;
const NO_STATIONS: StationLookup = { code: () => null, provider: () => null };
type StationRef = Readonly<{ ref: string | null; id: string | null; code: string | null }>;
const codeFor = (st: StationRef, s: StationLookup) => st.code ?? s.code(st.ref) ?? s.code(st.id);
const providerFor = (st: StationRef, s: StationLookup) => s.provider(st.ref) ?? s.provider(st.id);

export type ReadinessTag = Readonly<{ state: OpState; label: string; sentence: string | null }>;

/**
 * The pass's readiness tag (U33). `where: "drawer"` also says "Uplink ready"; bars and rows stay
 * quiet when ready. States are ready | qualifying | blocked (amendment 2; an older "recovering"
 * reads as qualifying). null readiness (no live uplink session) shows nothing.
 */
export function readinessTag(
  r: Readonly<{ state: string; reason: string | null; since: string | null }> & {
    command_groups_queued?: number | null | undefined;
  },
  where: "drawer" | "row",
  c: ReasonContext = {},
): ReadinessTag | null {
  const qualifying =
    r.state === "qualifying" ||
    r.state === "recovering" ||
    (r.reason !== null && r.reason in QUALIFYING);
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
  const tail = r.reason === RESTART ? " The next pass isn't affected." : "";
  return {
    state: (r.command_groups_queued ?? 1) > 0 ? "crit" : "caution",
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
export function groupBlockedLine(
  uplink: GroupUplink | null | undefined,
  expiresAt: string | null,
  stations: StationLookup = NO_STATIONS,
): string | null {
  const readiness = uplink?.readiness ?? null;
  if (!uplink || readiness?.state !== "blocked") return null;
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

const recovered = d.object({ state: d.token, ready_at: d.nullable(d.timestamp) });

export type RecoverOutcome = Readonly<{ tone: "nominal" | "info" | "caution"; text: string }>;

/** `Recover uplink` (U33): re-runs the automatic recovery; audited and safe to repeat, so no confirm. */
export async function recoverUplink(missionId: string, passId: string): Promise<RecoverOutcome> {
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
  const code = "code" in e ? e.code : null;
  if (code === "uplink_recovery_refused") {
    const details = "details" in e ? e.details : null;
    const reason =
      typeof details === "object" &&
      details !== null &&
      "reason" in details &&
      typeof details.reason === "string"
        ? details.reason
        : null;
    return {
      tone: "caution",
      text: `Recovery refused: ${reason ? reasonClause(reason) : "no reason given"}.`,
    };
  }
  if (code === "uplink_not_blocked")
    return { tone: "info", text: "The uplink isn't blocked any more." };
  if (code === "uplink_recovering") return { tone: "info", text: "Qualifying now." };
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
