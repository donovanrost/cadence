import { isKnown } from "@/api/index.ts";
import { short, type Attention, type PassChange, type ProviderChange } from "./attention.ts";

/**
 * §11 L14 provider changes to booked passes (api 30b3f60b9; ux U44). One item per change:
 * approval_required (decide before deadline_at), acknowledgment_required (the provider already
 * made it) or configuration_failure (Cadence couldn't apply it). Shared by Now's row and the
 * Contacts drawer block.
 */

type Field = ProviderChange["fields"][number];
type KnownField = Exclude<Field["field"], Readonly<{ unrecognized: string }>>;

/** U44: the server's label (api b5ecefaa2 fills the known keys), else these words, else Other. */
const FIELD_WORDS: Readonly<Record<KnownField, string>> = {
  starts_at: "AOS",
  ends_at: "LOS",
  ground_station_ref: "Station",
  antenna_or_service_pool_ref: "Antenna",
  service_profile_ref: "Service profile",
  delivery_profile_ref: "Delivery profile",
  spacecraft_ref: "Spacecraft",
  pass_phase: "Pass phase",
  status: "Status",
};
const TIME_FIELDS: readonly string[] = ["starts_at", "ends_at"];

export function fieldLabel(f: Field): string {
  if (f.label) return f.label;
  // ux U44: a field nobody has named shows as Other; its raw key stays in Technical details.
  return isKnown(f.field) ? FIELD_WORDS[f.field] : "Other";
}

/** The raw key, for Technical details only (never visible text, ux U44). */
export const fieldKey = (f: Field) => (isKnown(f.field) ? f.field : f.field.unrecognized);

/** A JSON-text value in words: §4 times, plain strings and numbers, `none`; never JSON quoting. */
export function valueWords(f: Field, json: string | null, now: Date): string {
  if (json === null) return "none";
  let v: unknown;
  try {
    v = JSON.parse(json);
  } catch {
    return json;
  }
  if (v === null || v === "") return "none";
  if (typeof v === "string")
    return TIME_FIELDS.includes(fieldKey(f)) && !Number.isNaN(Date.parse(v)) ? short(v, now) : v;
  // Numbers stay as the provider wrote them (64-bit safe: from the JSON text, not the parse).
  if (typeof v === "number") return json.trim();
  if (typeof v === "boolean") return v ? "yes" : "no";
  return "changed";
}

/** `Start 03:10Z → 03:12Z · Antenna 2 → 4`, at most 3, then "and 2 more" (U44). */
export function changeLine(pc: ProviderChange, now: Date): string {
  const shown = pc.fields
    .slice(0, 3)
    .map(
      (f) =>
        `${fieldLabel(f)} ${valueWords(f, f.before_json, now)} → ${valueWords(f, f.after_json, now)}`,
    );
  const more = pc.fields.length - shown.length;
  return [shown.join(" · "), more > 0 ? `and ${more} more` : null].filter(Boolean).join(" · ");
}

const passWords = (a: Attention, now: Date) =>
  [a.station?.code ?? a.station?.name, a.starts_at ? short(a.starts_at, now) : null]
    .filter(Boolean)
    .join(" ");

/** U44 titles, without the spacecraft prefix the row adds. */
export function changeTitle(a: Attention, now: Date): string {
  const provider = a.provider?.name ?? "The provider";
  const pass = `the ${passWords(a, now) || "booked"} pass`;
  switch (a.conflict) {
    case "acknowledgment_required":
      return `${provider} changed ${pass}`;
    case "configuration_failure":
      return `Cadence couldn't apply ${a.provider?.name ? `${a.provider.name}'s` : "the provider's"} change to ${pass}`;
    case "approval_required":
    // Other sources never reach here (the row and block are provider_change only).
    case "cancel_failed":
    case "late_confirmation":
    case "contradicts_attestation":
    case "unsettled":
    case "generation_not_applied":
    case "apply_failed":
    case "apply_stalled":
    case "not_started":
    case "missed":
    case "journal_near_full":
    case "frames_dropped":
    case "journal_disk":
    case "quarantined":
    case "listener_refusal":
    case "outcome_unknown":
    case "replay_id_conflict":
    case null:
    default:
      return `${provider} wants to change ${pass}`;
  }
}

/** The approval's deadline, if any. */
export const changeDeadline = (a: Attention) =>
  a.deadline_at ?? a.provider_change?.deadline_at ?? null;

/** api 84f58b73d: past it, neither approve nor reject is possible; the item waits for the provider. */
export const pastDeadline = (a: Attention, now: Date) => {
  const d = changeDeadline(a);
  return d !== null && Date.parse(d) <= now.getTime();
};

/** The changed fields, then "Decide by 02:40Z." / "Northlight already made this change." */
export function changeEvidence(a: Attention, now: Date): string {
  const pc = a.provider_change;
  const deadline = changeDeadline(a);
  const approval = a.conflict === "approval_required" && deadline !== null;
  const parts = [
    pc && pc.fields.length ? `${changeLine(pc, now)}.` : null,
    approval && !pastDeadline(a, now) ? `Decide by ${short(deadline, now)}.` : null,
    approval && pastDeadline(a, now) ? `The deadline passed at ${short(deadline, now)}.` : null,
    a.conflict === "acknowledgment_required"
      ? `${a.provider?.name ?? "The provider"} already made this change.`
      : null,
  ];
  return parts.filter(Boolean).join(" ");
}

/**
 * A pass's change history (ux U44 pass history): each entry leads with what changed, then its
 * outcome. Open states keep their decision block (`open`); an unknown state shows the evidence
 * alone; a change Cadence couldn't apply carries a crit mark.
 */
export type HistoryEntry = Readonly<{
  evidence: string;
  outcome: string | null;
  open: "approval_required" | "acknowledgment_required" | null;
  crit: boolean;
  /** A pending change whose pass ended undecided (the EXPIRED block when it's the newest). */
  expired: boolean;
}>;

const DECIDED: Readonly<Record<"approved" | "rejected" | "acknowledged", string>> = {
  approved: "Approved",
  rejected: "Rejected",
  acknowledged: "Acknowledged",
};

export function historyEntry(c: PassChange, provider: string | null, now: Date): HistoryEntry {
  const line = c.fields.length ? changeLine(c, now) : null;
  const evidence = `${provider ?? "The provider"} changed this pass${line ? `: ${line}` : ""}.`;
  const r = c.resolution;
  const entry = (outcome: string | null, extra: Partial<HistoryEntry> = {}): HistoryEntry => ({
    evidence,
    outcome,
    open: null,
    crit: false,
    expired: false,
    ...extra,
  });
  if (!isKnown(c.state)) return entry(null);
  switch (c.state) {
    case "approved":
    case "rejected":
    case "acknowledged": {
      const at = r ? ` at ${short(r.at, now)}` : "";
      const why = r?.reason ? `: ${r.reason.trim().replace(/[.!?]+$/, "")}` : "";
      return entry(`${DECIDED[c.state]} by ${r?.by?.name ?? "an operator"}${at}${why}.`);
    }
    case "policy_accepted":
      return entry(`Accepted by the mission's policy at ${short(r?.at ?? c.raised_at, now)}.`);
    case "superseded":
      return entry("Replaced by a newer change.");
    case "expired":
      // ux U44 (final): "ended", since the pass's ends_at decides it.
      return entry("Not decided: the pass ended first.", { expired: true });
    case "configuration_failure":
    case "apply_failed":
      return entry("Cadence couldn't apply it.", { crit: true });
    case "pending_approval":
      return entry(null, { open: "approval_required" });
    case "acknowledgment_required":
      return entry(null, { open: "acknowledgment_required" });
    case "observed":
      return entry(null);
  }
}
