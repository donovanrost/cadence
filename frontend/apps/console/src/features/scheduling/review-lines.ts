import type { PlanDetail } from "./api.ts";

/** U36 for the reviewer: who resubmitted, with their note, and the earlier round in text-3. */
export function resubmittedLines(
  plan: PlanDetail,
): Readonly<{ line: string; earlier: string | null }> | null {
  if (plan.state !== "pending_approval") return null;
  const { submission: sub, previous_round: prev } = plan;
  if (!sub || sub.round < 2) return null;
  const who = sub.actor.name ?? "The author";
  const at = `${sub.at.slice(11, 16)}Z`;
  const line = sub.note
    ? `Resubmitted by ${who} · ${at}: ${sub.note}`
    : sub.unchanged
      ? `Resubmitted unchanged by ${who} · ${at}`
      : `Resubmitted by ${who} · ${at}`;
  const a = prev?.approval;
  const earlier =
    a?.decision === "rejected"
      ? `Round ${prev?.round ?? sub.round - 1}: sent back by ${a.actor.name ?? "an org admin"} at ${a.at.slice(11, 16)}Z${a.reason ? `: ${a.reason}` : ""}`
      : null;
  return { line, earlier };
}

/** A draft an admin sent back: who, when and why, for its author (api 97523716). */
export function sentBackLine(plan: PlanDetail, userId: string, isAdmin: boolean): string | null {
  if (plan.state !== "draft") return null;
  const a = plan.approval;
  if (a?.decision !== "rejected") return null;
  const who = a.actor.name ?? "An org admin";
  const why = a.reason ? `: ${a.reason.trim().replace(/[.!?]+$/, "")}.` : ".";
  // The next step is the author's (qa): a reviewer looking at it just sees what was decided.
  const author = plan.author;
  const mine = author?.kind !== "system" && author?.id === userId;
  const next = mine || !isAdmin ? " Change the plan or its gap reasons, then submit it again." : "";
  return `Sent back by ${who} at ${a.at.slice(11, 16)}Z${why}${next}`;
}
