import { decoders as d, request, type ApiResult, type Decoded, type MissionId } from "@/api";
import { formatCount } from "@/ui";
import type { PlanDetail } from "./api.ts";

/**
 * A plan's history (ux U73, A10; api 7a83a958b `GET /contact-plans/:id/history`): its versions and
 * every submit and decision across all rounds, newest first. Versions read `R3`, as K1's header does.
 */

const actorKinds = ["user", "service_identity", "system"] as const;
const historyActor = d.object({
  kind: d.knownText(actorKinds),
  id: d.nullable(d.token),
  name: d.nullable(d.string),
});

const versionRow = d.object({
  version: d.integer,
  created_at: d.timestamp,
  created_by: d.nullable(historyActor),
  // free-text: the drafter's or re-plan's reason for this version
  rationale: d.nullable(d.string),
  selected: d.integer,
  locked: d.integer,
  rejected: d.integer,
  decision: d.nullable(d.knownText(["approved", "rejected"] as const)),
  submitted: d.boolean,
});

/** api f3aa9b272 (U73): which requirement a gap was, for its row; absent on older reads. */
const gapNames = {
  // free-text: the requirement's template name, else its rule in words
  requirement_label: d.optional(d.nullable(d.string)),
  spacecraft: d.optional(d.nullable(d.object({ id: d.token, name: d.nullable(d.string) }))),
  /** api 3386a8bf3 (U73): the requirement version's window, so a recurring rule's gaps differ. */
  requirement_window: d.optional(d.nullable(d.object({ from: d.timestamp, to: d.timestamp }))),
};

const decisionRow = d.object({
  kind: d.knownText(["submitted", "approved", "rejected"] as const),
  version: d.integer,
  round: d.nullable(d.integer),
  actor: d.nullable(historyActor),
  at: d.timestamp,
  // free-text: a submit's note or a decision's reason
  text: d.nullable(d.string),
  unchanged: d.nullable(d.boolean),
  acknowledgements: d.array(
    d.object({
      requirement_id: d.token,
      // free-text: why the author accepted this gap, as they wrote it
      reason: d.string,
      ...gapNames,
    }),
    2_000,
  ),
  exceptions: d.array(
    d.object({
      requirement_id: d.token,
      requirement_version: d.nullable(d.integer),
      // free-text: why the approver accepted this gap, as they wrote it
      reason: d.string,
      ...gapNames,
    }),
    2_000,
  ),
  automation_grant_id: d.nullable(d.token),
});

export const planHistoryReader = d.object({
  plan_id: d.token,
  latest_version: d.integer,
  versions: d.array(versionRow, 200),
  decisions: d.array(decisionRow, 500),
  truncated: d.boolean,
});
export type PlanHistory = Decoded<typeof planHistoryReader>;
export type VersionRow = PlanHistory["versions"][number];
export type DecisionRow = PlanHistory["decisions"][number];

export function fetchPlanHistory(
  missionId: MissionId,
  planId: string,
  signal?: AbortSignal,
): Promise<ApiResult<PlanHistory>> {
  return request(
    `/missions/${encodeURIComponent(missionId)}/contact-plans/${encodeURIComponent(planId)}/history`,
    planHistoryReader,
    signal ? { signal } : {},
  );
}

/** `02:44Z` today, else `11-13 02:44Z` (§4). */
export function when(iso: string, now: Date = new Date()): string {
  const time = `${iso.slice(11, 16)}Z`;
  return iso.slice(0, 10) === now.toISOString().slice(0, 10) ? time : `${iso.slice(5, 10)} ${time}`;
}

/** A person or service by name; Cadence's planner as "Cadence" (U73). */
function who(a: DecisionRow["actor"], fallback: string): string {
  if (!a) return fallback;
  if (a.name) return a.name;
  return a.kind === "system" ? "Cadence" : fallback;
}

const quote = (s: string | null) => (s?.trim() ? `“${s.trim()}”` : null);

export type HistoryLine = Readonly<{
  key: string;
  at: string;
  line: string;
  /** A quoted note, reason or rationale, on its own line. */
  quote: string | null;
  /** A version's counts (text-3). */
  counts: string | null;
  /** CURRENT (neutral: no state), and the version's decision as a word tag. */
  tags: readonly Readonly<{ label: string; state: "nominal" | "caution" | null }>[];
  /** `View R3` (not on the current version). */
  view: number | null;
  /** Gaps accepted at submit, or exceptions at approval, under `Show`. */
  /** `text` is the row (ux: no raw id leads it); `id` goes under Technical details. */
  details: readonly Readonly<{ id: string; text: string }>[];
  detailsLabel: string | null;
}>;

export function versionLine(v: VersionRow, current: number, now: Date = new Date()): HistoryLine {
  const by = v.created_by ? ` by ${who(v.created_by, "someone")}` : "";
  const decision =
    v.decision === "approved"
      ? { label: "APPROVED", state: "nominal" as const }
      : v.decision === "rejected"
        ? { label: "SENT BACK", state: "caution" as const }
        : null;
  return {
    key: `v${v.version}`,
    at: v.created_at,
    line: `R${v.version} · drafted${by} at ${when(v.created_at, now)}`,
    quote: quote(v.rationale),
    counts: `${formatCount(v.selected)} selected · ${formatCount(v.locked)} locked · ${formatCount(v.rejected)} rejected`,
    tags: [
      ...(v.version === current ? [{ label: "CURRENT", state: null }] : []),
      ...(decision ? [decision] : []),
    ],
    view: v.version === current ? null : v.version,
    details: [],
    detailsLabel: null,
  };
}

type Gap = DecisionRow["acknowledgements"][number] | DecisionRow["exceptions"][number];
/** 'EARENDIL-389 · Block 1 daily: no window can cover it' (U73); the reason alone without names. */
/**
 * A gap's window (ux U73, §4): times only when it lies on the plan's day, else both ends dated
 * ('11-16 22:00–11-17 02:00Z'). An end at 00:00 belongs to the day before.
 */
export function gapWindow(
  w: Readonly<{ from: string; to: string }>,
  planDay: string | null,
): string {
  const toDay = new Date(Date.parse(w.to) - 1).toISOString().slice(0, 10);
  const onDay = planDay !== null && w.from.slice(0, 10) === planDay && toDay === planDay;
  const at = (iso: string) => `${iso.slice(11, 16)}`;
  return onDay
    ? `${at(w.from)}–${at(w.to)}Z`
    : `${w.from.slice(5, 10)} ${at(w.from)}–${w.to.slice(5, 10)} ${at(w.to)}Z`;
}

export function gapText(g: Gap, planDay: string | null = null): string {
  const name = [
    g.spacecraft?.name ?? null,
    g.requirement_label ?? null,
    g.requirement_window ? gapWindow(g.requirement_window, planDay) : null,
  ]
    .filter((p): p is string => Boolean(p))
    .join(" · ");
  return name ? `${name}: ${g.reason}` : g.reason;
}

export function decisionLine(
  e: DecisionRow,
  now: Date = new Date(),
  planDay: string | null = null,
): HistoryLine {
  const t = when(e.at, now);
  const r = `R${e.version}`;
  const base = { key: `d${e.version}-${e.at}`, at: e.at, counts: null, tags: [], view: null };
  if (e.kind === "submitted") {
    const n = e.acknowledgements.length;
    const lead = e.unchanged
      ? `Resubmitted ${r} unchanged by ${who(e.actor, "the author")} at ${t}`
      : `Submitted ${r} for approval by ${who(e.actor, "the author")} at ${t}`;
    return {
      ...base,
      line: n > 0 ? `${lead} · ${formatCount(n)} ${n === 1 ? "gap" : "gaps"} accepted` : lead,
      quote: quote(e.text),
      details: e.acknowledgements.map((a) => ({ id: a.requirement_id, text: gapText(a, planDay) })),
      detailsLabel: n > 0 ? `Show ${formatCount(n)}` : null,
    };
  }
  if (e.kind === "approved") {
    const n = e.exceptions.length;
    // No policy name on the wire yet: "under an automation policy" (U73's fallback).
    const lead = e.automation_grant_id
      ? `Approved ${r} automatically under an automation policy at ${t}`
      : `Approved ${r} by ${who(e.actor, "an org admin")} at ${t}`;
    return {
      ...base,
      line: n > 0 ? `${lead} · ${formatCount(n)} ${n === 1 ? "exception" : "exceptions"}` : lead,
      quote: quote(e.text),
      details: e.exceptions.map((x) => ({ id: x.requirement_id, text: gapText(x, planDay) })),
      detailsLabel: n > 0 ? `Show ${formatCount(n)}` : null,
    };
  }
  if (e.kind === "rejected") {
    const why = quote(e.text);
    return {
      ...base,
      line: `Sent back ${r} by ${who(e.actor, "an org admin")} at ${t}${why ? `: ${why}` : ""}`,
      quote: null,
      details: [],
      detailsLabel: null,
    };
  }
  // An act this console doesn't know yet still says which version and when.
  return {
    ...base,
    line: `${e.kind.unrecognized.replaceAll("_", " ")} ${r} at ${t}`,
    quote: quote(e.text),
    details: [],
    detailsLabel: null,
  };
}

/** One list, newest first: version rows and decision rows in time order (U73). */
export function historyLines(
  h: PlanHistory,
  now: Date = new Date(),
  planDay: string | null = null,
): readonly HistoryLine[] {
  return [
    ...h.versions.map((v) => versionLine(v, h.latest_version, now)),
    ...h.decisions.map((e) => decisionLine(e, now, planDay)),
  ].sort((a, b) => (a.at < b.at ? 1 : a.at > b.at ? -1 : 0));
}

/** `?version=N` of an older version: read-only (U73). Null on the current one or older reads. */
export function historical(plan: PlanDetail): number | null {
  return plan.latest_version != null && plan.version < plan.latest_version
    ? plan.latest_version
    : null;
}

/** The old version's callout, worded by that version's own decision (U73). */
export function oldVersionLine(plan: PlanDetail, latest: number, now: Date = new Date()): string {
  const r = `R${plan.version}`;
  const a = plan.approval;
  if (a?.decision === "rejected")
    return `You're looking at ${r}, sent back ${when(a.at, now)}. The current version is R${latest}.`;
  if (a?.decision === "approved")
    return `You're looking at ${r}, approved ${when(a.at, now)} and since replaced by R${latest}.`;
  if (plan.submission)
    return `You're looking at ${r}, submitted ${when(plan.submission.at, now)} and since replaced by R${latest}.`;
  return `You're looking at ${r}, never submitted. The current version is R${latest}.`;
}
