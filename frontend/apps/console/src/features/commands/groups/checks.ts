import type { Scid } from "@/api/index.ts";
import { plural, type OpState } from "@/ui";
import { isKnown, type Unrecognized } from "@/api/index.ts";
import {
  checkKeys,
  checkKeyText,
  type CheckKey,
  type CheckResult,
  type Preflight,
  type PreflightCheck,
  type TwoPersonReason,
} from "./api.ts";
import type { GroupEvent } from "./show.ts";
import { withdrawnSentence } from "./withdrawnSentence.ts";

/**
 * Preflight checks → poll rows (Command.md C3, CommandFlow A2). Only checks the server computed
 * appear; a missing check is absent, never green. Sentences name targets by name + SCID.
 */
export const RESULT_STATE: Readonly<Record<CheckResult, OpState>> = {
  go: "nominal",
  second_go: "neutral",
  hold: "caution",
  no_go: "crit",
};
export const RESULT_WORD: Readonly<Record<CheckResult, string>> = {
  go: "GO",
  second_go: "2ND GO",
  hold: "HOLD",
  no_go: "NO-GO",
};

const LABELS: Readonly<Record<CheckKey, string>> = {
  identity: "Identity",
  catalog: "Catalog",
  size: "Size",
  conflicts: "Conflicts",
  contact: "Contact",
  two_person: "Two-person",
  changed_since_submit: "Since submit",
  // U109: mapped by key, never by text.
  model_approval_withdrawn: "Composition",
};

/** commanding.md: why a target's identity doesn't resolve (per_target reason). */
const identityFailures = [
  "no_uplink_route",
  "multiple_primary_uplink_routes",
  "no_source_endpoint",
  "ambiguous_source_endpoint",
  "source_endpoint_not_found",
  "missing_scid",
] as const;
const IDENTITY_WORDS: Readonly<Record<(typeof identityFailures)[number], string>> = {
  no_uplink_route: "has no primary uplink route",
  multiple_primary_uplink_routes: "has several primary uplink routes",
  no_source_endpoint: "has no uplink endpoint",
  ambiguous_source_endpoint: "has several uplink endpoints",
  source_endpoint_not_found: "endpoint not found",
  missing_scid: "has no SCID",
};

/** A per-target identity failure in words; a code the console doesn't know reads as words. */
function identityWords(reason: string): string {
  const known = identityFailures.find((k) => k === reason);
  return known ? IDENTITY_WORDS[known] : reason.replaceAll("_", " ");
}

export type TargetName = (spacecraftId: string) => string;

/** Structurally an ApCheckRow (declared here so plain TS sees the type, not the SFC). */
export type CheckRow = Readonly<{
  key: string;
  label: string;
  sentence: string;
  state: OpState;
  verdict: string;
  /** Where to fix it, when the check names one (identity → the profile's routing). */
  profileId?: string;
}>;

/** A check the console doesn't know yet still shows, labelled from its key. */
const words = (key: string) => {
  const w = key.replaceAll("_", " ");
  return w.charAt(0).toUpperCase() + w.slice(1);
};

function list(names: readonly string[], max = 4): string {
  const shown = names.slice(0, max).join(", ");
  return names.length > max ? `${shown} and ${names.length - max} more` : shown;
}

export function reasonWord(r: TwoPersonReason): string {
  switch (r.key) {
    case "hazardous_command":
      return `${r.name ?? "A command"} is hazardous`;
    case "critical_command":
      return `${r.name ?? "A command"} is critical`;
    case "policy_hint":
      return `${r.name ?? "A command"} asks for a second GO`;
    case "fleet_reach":
      return `${r.targets ?? "Many"} targets is fleet reach (${r.threshold ?? 10} or more)`;
    default:
      return (isKnown(r.key) ? r.key : r.key.unrecognized).replaceAll("_", " ");
  }
}

function sentence(check: PreflightCheck, pf: Preflight, nameOf: TargetName): string {
  const failed = check.per_target.filter((t) => t.result !== "go");
  const names = failed.map((t) => nameOf(t.spacecraft_id));
  const ev = check.evidence;
  switch (check.key) {
    case "identity": {
      if (check.result === "go") {
        const scids = pf.targets.map((t) => t.scid).filter((s): s is Scid => s !== null);
        const n = pf.targets.length;
        return `${n === 1 ? "The target resolves" : `All ${n} targets resolve`} · SCID ${list(scids.map(String), 6)}`;
      }
      return failed
        .map(
          (t) =>
            `${nameOf(t.spacecraft_id)} ${typeof t.reason === "string" ? identityWords(t.reason) : "doesn't resolve"}`,
        )
        .slice(0, 4)
        .join("; ");
    }
    case "catalog":
      return check.result === "go"
        ? "Every command is valid for every target, arguments in range"
        : `Not valid on ${list(names)}`;
    case "size":
      return check.result === "go"
        ? `${plural(ev.targets ?? 0, "target")} × ${plural(ev.commands ?? 0, "command")}, within bounds`
        : `Too large: up to ${ev.max_targets ?? "?"} targets, ${ev.max_commands ?? "?"} commands, ${ev.max_members ?? "?"} uplinks per request`;
    case "conflicts":
      return check.result === "go"
        ? "No competing uplinks queued"
        : `${plural(ev.count ?? 0, "request")} already queued or awaiting GO on these targets`;
    case "contact":
      // #60 (5): only bookings with a confirmed uplink leg count, from max(now, not_before).
      return check.result === "go"
        ? "Every target has a booked contact with a confirmed uplink"
        : `No booked contact with a confirmed uplink for ${list(names)} in the release window`;
    case "two_person":
      return check.result === "go"
        ? "No second GO needed"
        : `Needs a second operator's GO: ${(ev.reasons ?? []).map(reasonWord).join("; ")}`;
    case "changed_since_submit":
      return check.result === "go"
        ? "Same targets, catalog and values as submitted"
        : "Something changed since it was submitted (catalog, targets or values)";
    case "model_approval_withdrawn":
      return withdrawnSentence(check, pf, nameOf);
    default:
      return `${words(checkKeyText(check.key))}: ${RESULT_WORD[check.result]}`;
  }
}

/** The first profile whose routing an identity NO-GO points at. */
export function routingProfile(check: PreflightCheck): string | null {
  if (check.key !== "identity" || check.result === "go") return null;
  for (const t of check.per_target)
    for (const r of t.routes ?? []) if (r.profile_id) return r.profile_id;
  return null;
}

export function checkRows(pf: Preflight, nameOf: TargetName): CheckRow[] {
  return pf.checks.map((c) => {
    const profileId = routingProfile(c);
    return {
      key: checkKeyText(c.key),
      label: checkLabel(c.key),
      sentence: sentence(c, pf, nameOf),
      state: RESULT_STATE[c.result],
      verdict: RESULT_WORD[c.result],
      ...(profileId ? { profileId } : {}),
    };
  });
}

/** Header meta `5 GO · 1 HOLD`. */
export function checkMeta(pf: Preflight): string {
  const n = (r: CheckResult) => pf.checks.filter((c) => c.result === r).length;
  return (["go", "second_go", "hold", "no_go"] as const)
    .filter((r) => n(r) > 0)
    .map((r) => `${n(r)} ${RESULT_WORD[r]}`)
    .join(" · ");
}

/** The first NO-GO, in words, for the commit button's reason. */
export function noGoReason(pf: Preflight, nameOf: TargetName): string | null {
  const bad = pf.checks.find((c) => c.result === "no_go");
  return bad ? `${checkLabel(bad.key)} NO-GO: ${sentence(bad, pf, nameOf)}.` : null;
}

/** A check's label from its key (decoded, or as text): the console's word, else the key in words. */
export function checkLabel(key: Unrecognized | string): string {
  const text = typeof key === "string" ? key : key.unrecognized;
  const known = checkKeys.find((k) => k === text);
  return known ? LABELS[known] : words(text);
}

/** An operator's acks so far, by check key: the note and the hold_basis it was written against. */
export type HoldAcks = Readonly<Record<string, Readonly<{ basis: string | null; note: string }>>>;

/**
 * HOLDs that gate Arm (#60). two_person is the approval step itself, never a gate (older servers
 * still send it as HOLD); changed_since_submit is review-only.
 */
export function gatingHolds(pf: Preflight): PreflightCheck[] {
  return pf.checks.filter(
    (c) => c.result === "hold" && c.key !== "two_person" && c.key !== "changed_since_submit",
  );
}

/** An ack counts while its note is written and its basis matches the HOLD as it stands now. */
export const ackCounts = (c: PreflightCheck, acks: HoldAcks) => {
  const a = acks[checkKeyText(c.key)];
  return (
    c.ackable !== false &&
    a !== undefined &&
    a.note.trim() !== "" &&
    a.basis === (c.hold_basis ?? null)
  );
};

/** Why Arm stays closed over a HOLD, in words; null when every HOLD is acked or there are none. */
export function holdReason(pf: Preflight, acks: HoldAcks, nameOf: TargetName): string | null {
  const holds = gatingHolds(pf);
  const hard = holds.find((c) => c.ackable === false);
  if (hard) return `${checkLabel(hard.key)} HOLD: ${sentence(hard, pf, nameOf)}. Clear it to arm.`;
  const open = holds.filter((c) => !ackCounts(c, acks));
  if (!open.length) return null;
  return `Acknowledge the ${open.map((c) => checkLabel(c.key)).join(" and ")} HOLD with a note, or clear it.`;
}

/** The acks to send: one per gating HOLD that's acked against its current facts. */
export function holdAcksToSend(
  pf: Preflight,
  acks: HoldAcks,
): { key: string; hold_basis: string | null; note: string }[] {
  return gatingHolds(pf)
    .filter((c) => ackCounts(c, acks))
    .map((c) => ({
      key: checkKeyText(c.key),
      hold_basis: c.hold_basis ?? null,
      note: (acks[checkKeyText(c.key)]?.note ?? "").trim(),
    }));
}

/**
 * #61 Approve: GO re-runs the review preflight. Hard HOLDs (contact, changed_since_submit) refuse
 * GO; an ackable HOLD is covered when a hold_acknowledged event already matches its key and
 * basis, else the approver acks it. two_person never gates.
 */
export function reviewHolds(pf: Preflight | null, events: readonly GroupEvent[]) {
  const holds = (pf?.checks ?? []).filter((c) => c.result === "hold" && c.key !== "two_person");
  const covered = (c: PreflightCheck) =>
    events.some(
      (e) =>
        e.kind === "hold_acknowledged" &&
        e.payload?.key === c.key &&
        (e.payload.hold_basis ?? null) === (c.hold_basis ?? null),
    );
  return {
    hard: holds.filter((c) => c.ackable === false),
    covered: holds.filter((c) => c.ackable !== false && covered(c)),
    open: holds.filter((c) => c.ackable !== false && !covered(c)),
  };
}

/** Why GO stays closed over the review's HOLDs, in words; null when GO may go. */
export function goHoldReason(
  pf: Preflight | null,
  events: readonly GroupEvent[],
  acks: HoldAcks,
  nameOf: TargetName,
): string | null {
  if (!pf) return null;
  const { hard, open } = reviewHolds(pf, events);
  const h = hard[0];
  if (h)
    return `${checkLabel(h.key)} HOLD: ${sentence(h, pf, nameOf)}. GO is refused; send it back or give NO-GO.`;
  const unacked = open.filter((c) => !ackCounts(c, acks));
  return unacked.length
    ? `Acknowledge the ${unacked.map((c) => checkLabel(c.key)).join(" and ")} HOLD with a note first.`
    : null;
}

/** The approver's acks to send with GO: open HOLDs acked against their current basis. */
export function goAcksToSend(pf: Preflight | null, events: readonly GroupEvent[], acks: HoldAcks) {
  return reviewHolds(pf, events)
    .open.filter((c) => ackCounts(c, acks))
    .map((c) => ({
      key: checkKeyText(c.key),
      hold_basis: c.hold_basis ?? null,
      note: (acks[checkKeyText(c.key)]?.note ?? "").trim(),
    }));
}
