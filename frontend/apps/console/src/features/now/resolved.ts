import { isKnown, type Decoded } from "@/api/index.ts";
import type { QueueItem } from "./queue.ts";
import type { ResolutionAction } from "./attentionVocab.ts";
import type { resolvedReader } from "./attentionReader.ts";
import { noStop, short } from "./attentionWords.ts";
import { diskResolvedWords } from "./journalDisk.ts";

/** Resolved attention rows (U31/U32): what closed each, and the 5 s fade at its old place. */

export type Resolved = Decoded<typeof resolvedReader>;
/** What the words read of a resolved entry; `booked` and `refused` are only on newer reads. */
export type ResolvedEntry = Omit<
  Resolved,
  "booked" | "refused" | "from_state" | "plan_revision" | "booking" | "path" | "realized_contact_id"
> &
  Readonly<{
    realized_contact_id?: Resolved["realized_contact_id"];
    path?: Resolved["path"];
    booked?: boolean | null | undefined;
    refused?: Resolved["refused"];
    from_state?: Resolved["from_state"];
    plan_revision?: Resolved["plan_revision"];
    booking?: Resolved["booking"];
  }>;

/** Server actions that read better in words: U37's system 'replayed' = the telemetry got stored. */
const ACTION_WORDS: Readonly<Partial<Record<ResolutionAction, string>>> = {
  replayed: "telemetry stored",
  // U38: the runtime caught up with the active configuration.
  applied: "configuration applied",
};

/**
 * What closed it (ops.md §resolved, U32): a person reads "Resolved by Mira K."; a provider
 * "Resolved: Northlight confirmed"; the system its action alone ("Resolved: cancel confirmed").
 * Never "by Cadence".
 */
const CHANGE_DECIDED: Readonly<Partial<Record<ResolutionAction, string>>> = {
  approved: "Approved",
  rejected: "Rejected",
  acknowledged: "Acknowledged",
};

export function resolvedWords(r: ResolvedEntry, now: Date = new Date()): string {
  // §4 short form: a row resolved before midnight keeps its date after it (ux).
  const at = short(r.resolved_at, now);
  // U41: a stuck activation closes by applying, or by a newer activation replacing it.
  // U44: a provider change says who decided, when and why; a newer change replaces it.
  if (r.id.startsWith("attention:provider_change:")) {
    const decided = r.action && isKnown(r.action) ? CHANGE_DECIDED[r.action] : undefined;
    if (r.action === "superseded") return "Replaced by a newer change.";
    if (decided) {
      const who = r.resolved_by.name ?? "an operator";
      const why = r.note ? `: ${noStop(r.note)}` : "";
      return `${decided} by ${who} at ${at}${why}.`;
    }
  }
  if (r.id.startsWith("attention:contact_start:")) {
    // U45: it started, or an operator marked the missed pass as seen. A pass that failed to set
    // up (realized_contact_id null) reads "Set up", since its start can still fail (ux).
    if (r.action === "started")
      return r.realized_contact_id === null ? `Set up at ${at}.` : `Started at ${at}.`;
    if (r.action === "acknowledged")
      return `Marked as seen by ${r.resolved_by.name ?? "an operator"} at ${at}.`;
  }
  // compared-as-text: an item id (an open set); this is the one journal_disk item's fixed id (U66)
  if (r.id === "attention:ingress_backpressure:journal_disk")
    return diskResolvedWords(at, r.refused);
  if (r.id.startsWith("attention:ingress_backpressure:")) {
    // U47: the buffer caught up, or an operator acknowledged the lost frames.
    if (r.action === "drained") return `Caught up at ${at}.`;
    if (r.action === "acknowledged")
      return `Acknowledged by ${r.resolved_by.name ?? "an operator"} at ${at}.`;
  }
  if (r.id.startsWith("attention:archive_quarantine:")) {
    // U49: archived on retry, discarded by an operator with a reason, or expired (#791).
    if (r.action === "retried") return `Archived on retry at ${at}.`;
    if (r.action === "expired")
      return `Expired at ${at}: nobody retried or discarded it before its retention ran out.`;
    if (r.action === "discarded")
      return `Discarded by ${r.resolved_by.name ?? "an operator"} at ${at}${r.note ? `: ${noStop(r.note)}` : ""}.`;
  }
  if (r.id.startsWith("attention:listener_refusal:")) {
    // U50: the pass got its own connection, or its window closed.
    if (r.action === "accepted") return `Connected at ${at}.`;
    // ux: without the booked flag, "Ended at" is true of a pass and a hand-started contact.
    if (r.action === "ended")
      return r.booked === true
        ? `The pass ended at LOS ${at}.`
        : r.booked === false
          ? `The contact ended at ${at}.`
          : `Ended at ${at}.`;
  }
  if (r.id.startsWith("attention:plan_coverage:")) {
    // U61: approved, nothing left to plan, or the day ended unplanned (crit, kept in the list).
    const day = r.id.slice("attention:plan_coverage:".length).slice(5, 10);
    if (r.action === "approved")
      return `Approved by ${r.resolved_by.name ?? "an org admin"} at ${at}.`;
    if (r.action === "nothing_left") return `Nothing is left to plan for ${day}.`;
    // ux 11fe550bf: booking began (from approved) or resumed (from interrupted).
    if (r.action === "booking_started")
      return r.from_state === "interrupted"
        ? `Booking continued at ${at}.`
        : `Booking started at ${at}.`;
    if (r.action === "day_ended") {
      const rv = r.plan_revision != null ? `R${r.plan_revision}` : "its plan";
      if (r.from_state === "approved" && !r.booking)
        return `${day} ended with ${rv} approved but not booked.`;
      if (r.from_state === "interrupted" && r.booking)
        return `${day} ended with ${r.booking.reserved} of ${r.booking.total} passes booked.`;
      return `${day} ended with no approved plan.`;
    }
  }
  if (r.id.startsWith("attention:job_outcome_unknown:")) {
    // U54: retried (queued again) or closed with what the operator found.
    const who = r.resolved_by.name ?? "an operator";
    if (r.action === "retried") return `Retried by ${who} at ${at}; it's queued.`;
    if (r.action === "closed")
      return r.note
        ? `Closed without retry by ${who} at ${at}: “${r.note.trim()}”`
        : `Closed without retry by ${who} at ${at}.`;
  }
  if (r.id.startsWith("attention:contact_scid_mismatch:")) {
    // U81 §2: never as if someone saw it when it retired unseen.
    if (r.action === "retired") return "Retired after 7 days without being seen.";
    if (r.action === "seen")
      return r.resolved_by.name ? `Seen by ${r.resolved_by.name} at ${at}.` : `Seen at ${at}.`;
  }
  if (r.id.startsWith("attention:replay_conflict:") && r.action === "resumed") {
    // U84: the system closed it when the fix landed; the action only, by path (U31).
    if (r.path === "storage") return "Resolved: telemetry storage resumed.";
    if (r.path === "timer") return "Resolved: timed actions running.";
    return "Resolved: processing resumed.";
  }
  // U91: the runtime is back on the active configuration.
  if (r.id.startsWith("attention:mission_runtime:") && r.action === "applied")
    return "Resolved: runtime started.";
  if (r.id.startsWith("attention:activation_apply:")) {
    if (r.action === "superseded") return "Replaced by a newer request.";
    if (r.action === "applied") return `Applied at ${at}.`;
  }
  const said = !r.action
    ? null
    : isKnown(r.action)
      ? (ACTION_WORDS[r.action] ?? r.action.replaceAll("_", " "))
      : r.action.unrecognized.replaceAll("_", " ");
  const action = said ? noStop(said) : null;
  const name = r.resolved_by.name ? noStop(r.resolved_by.name) : null;
  if (r.resolved_by.kind === "user") return `Resolved by ${name ?? "an operator"}.`;
  if (r.resolved_by.kind === "provider")
    return `Resolved: ${[name ?? "the provider", action].filter(Boolean).join(" ")}.`;
  return action ? `Resolved: ${action}.` : "Resolved.";
}

/** How long a resolved row stays, faded, before it leaves (U31). */
export const RESOLVED_FADE_MS = 5_000;

export type Fading = Readonly<{ item: QueueItem; index: number; until: number }>;

/**
 * Rows to fade after a read: a row seen last time, now gone, and listed in `resolved` reads
 * "Resolved by Mira K." for 5 s at its old place. It never takes the primary action.
 */
export function newlyResolved(
  previous: readonly QueueItem[],
  current: readonly QueueItem[],
  resolved: readonly ResolvedEntry[],
  already: readonly Fading[],
  now: number,
): Fading[] {
  const live = new Set(current.flatMap((r) => [r.key, ...(r.memberKeys ?? [])]));
  const seen = new Set(already.map((f) => f.item.key));
  return resolved.flatMap((r) => {
    // A folded row (U37) fades only once none of its members is still on screen.
    const index = previous.findIndex((p) => p.key === r.id || p.memberKeys?.includes(r.id));
    const prev = previous[index];
    if (!prev) return [];
    const key = `${prev.key}|resolved`;
    const members = prev.memberKeys ?? [prev.key];
    if (live.has(prev.key) || members.some((k) => live.has(k)) || seen.has(key)) return [];
    seen.add(key);
    const { list: _list, memberKeys: _members, ...rest } = prev;
    const item: QueueItem = {
      ...rest,
      key,
      state: "off",
      sentence: resolvedWords(r, new Date(now)),
      meta: null,
      acknowledged: true,
    };
    return [{ item, index, until: now + RESOLVED_FADE_MS }];
  });
}

/** Current rows with the fading ones put back where they were. */
export function withFading(rows: readonly QueueItem[], fading: readonly Fading[]): QueueItem[] {
  const out = [...rows];
  for (const f of [...fading].sort((a, b) => a.index - b.index))
    out.splice(Math.min(f.index, out.length), 0, f.item);
  return out;
}
