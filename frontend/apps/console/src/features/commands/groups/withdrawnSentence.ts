import type { Preflight, PreflightCheck } from "./api.ts";
import { compositionName, holdOneLine, holdSeveralLine } from "./withdrawn.ts";

/**
 * U109: the Composition check's sentence. One held target names it, its composition and the
 * decision; several are counted and listed (names only, never ids: the caller's nameOf).
 */
export function withdrawnSentence(
  check: PreflightCheck,
  pf: Preflight,
  nameOf: (spacecraftId: string) => string,
): string {
  const held = check.per_target.filter((t) => t.result !== "go");
  if (check.result === "go" || held.length === 0)
    return "Every target is on an approved composition";
  const [one] = held;
  if (held.length === 1 && one)
    return holdOneLine(nameOf(one.spacecraft_id), compositionName(one.composition), {
      kind: one.kind,
      decided_by: one.decided_by,
      decided_at: one.decided_at,
      reason: one.reason_text,
    });
  return holdSeveralLine(
    held.map((t) => nameOf(t.spacecraft_id)),
    pf.targets.length,
  );
}

/** How many targets the Composition HOLD holds (its ack note's placeholder counts them). */
export const heldCount = (check: PreflightCheck) =>
  check.per_target.filter((t) => t.result !== "go").length;
