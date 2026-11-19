import { actor, decoders as d } from "@/api/index.ts";

/**
 * plan_coverage (ux U61; api's wire 11-15, domain 47aabe3ba): one attention item per UTC day, from
 * today to +2, whose first contact window approaches without an approved plan. Its own fields,
 * spread into the attention reader: all optional (readers first) and null on other sources.
 */

/**
 * The day's newest plan, in the plan read's own lifecycle words. A sent-back plan is back in
 * `draft` with `sent_back` set; any other state still reads (knownText).
 */
export const coveragePlanStates = ["pending_approval", "draft", "approved", "interrupted"] as const;

const coveragePlan = d.object({
  id: d.token,
  revision: d.integer,
  state: d.knownText(coveragePlanStates),
  author: d.nullable(actor),
  submitted_at: d.nullable(d.timestamp),
  /** approved / interrupted only (domain 702223355). */
  approved_at: d.optional(d.nullable(d.timestamp)),
  /** interrupted only; last_progress_at is the last progress seen, not when it stopped. */
  booking: d.optional(
    d.nullable(
      d.object({
        reserved: d.integer,
        total: d.integer,
        last_progress_at: d.nullable(d.timestamp),
      }),
    ),
  ),
  sent_back: d.nullable(
    d.object({
      by: d.nullable(actor),
      at: d.timestamp,
      // free-text: the reviewer's comment
      comment: d.nullable(d.string),
    }),
  ),
});

export const planCoverageFields = {
  /** The UTC day, `YYYY-MM-DD` (also the item's id). */
  day: d.optional(d.nullable(d.string)),
  first_window_at: d.optional(d.nullable(d.timestamp)),
  /** The countdown target: the first window. */
  due_at: d.optional(d.nullable(d.timestamp)),
  /** caution before the first window opens; crit once it has, with nothing approved. */
  severity: d.optional(d.nullable(d.knownText(["caution", "crit"] as const))),
  requirements_count: d.optional(d.nullable(d.integer)),
  open_requirements_count: d.optional(d.nullable(d.integer)),
  /** null: the day has no plan yet. */
  plan: d.optional(d.nullable(coveragePlan)),
  /** Who can approve it, never the author. */
  approvers: d.optional(d.nullable(d.array(actor, 200))),
  /** Per request: the viewer is an approver and not the author. */
  viewer_can_approve: d.optional(d.nullable(d.boolean)),
  /** Per request: the viewer may POST …/execute (operate_mission): Start / Continue booking. */
  viewer_can_book: d.optional(d.nullable(d.boolean)),
};
