import type { RuntimeStatus } from "@/shell";

/**
 * Changes.md §2/§3 after commit, in U38's verbs (ux): the config is active and the runtime is
 * `applying` it (a newer generation waits) or has `not_applied` it (lead's U38 banner says why).
 * null when there's nothing to say: no read, applied, or an unknown state.
 */
export type ConfigRuntime = "applying" | "not_applied" | null;

export function configRuntime(runtime: RuntimeStatus | null | undefined): ConfigRuntime {
  if (!runtime) return null;
  // lead: applying = a newer generation waits with no failure reason; a reason means it failed.
  if (runtime.reason) return runtime.state === "not_applied" ? "not_applied" : null;
  const desired = runtime.desired_generation ?? null;
  const applied = runtime.applied_generation ?? null;
  if (desired !== null && applied !== null && desired > applied) return "applying";
  // Not applied with nothing newer waiting: the U38 banner's outage.
  return runtime.state === "not_applied" ? "not_applied" : null;
}

/** The top bar's suffix (ux): `CONFIG r6 · APPLYING` / `CONFIG r6 · NOT APPLIED`. */
export const runtimeWord: Readonly<Record<NonNullable<ConfigRuntime>, string>> = {
  applying: "APPLYING",
  not_applied: "NOT APPLIED",
};

/** The submit result's snapshot of the runtime at apply time (actions.ts SubmitResult). */
export type SubmitRuntime = "not_applicable" | "converging" | "applied" | "degraded";

export type OutcomeRuntime = "none" | "applying" | "applied" | "not_applied";

/**
 * After Apply (ux, Changes.md §3): the live runtime when we have it, else the submit snapshot.
 * `sawApplying`: the live read showed it applying since this apply, so a later quiet read means
 * it has applied; without that, a quiet read may only be stale, so the snapshot stands.
 */
export function outcomeRuntime(
  submitted: SubmitRuntime,
  live: ConfigRuntime | undefined,
  sawApplying: boolean,
): OutcomeRuntime {
  if (live === "not_applied") return "not_applied";
  if (live === "applying") return "applying";
  if (live === null && sawApplying) return "applied";
  return submitted === "converging"
    ? "applying"
    : submitted === "degraded"
      ? "not_applied"
      : submitted === "applied"
        ? "applied"
        : "none";
}

/** Retrying can't clear these: a fault in Cadence (domain, ux U91, as the banner says). */
const NEEDS_FIX: ReadonlySet<string> = new Set(["spec_mismatch", "reconcile_crashed"]);

/**
 * ux: the config is active, the runtime applies it. `r6 is active · 2 changes. The runtime is
 * applying it.` / `r6 is active and the runtime has applied it · 2 changes.` / `r6 is active, but
 * the runtime hasn't applied it yet.` (+ "It needs a fix in Cadence." as U91 says).
 */
export function outcomeText(
  revision: number,
  changes: string,
  runtime: OutcomeRuntime,
  reason: string | null,
): Readonly<{ tone: "nominal" | "caution"; text: string }> {
  switch (runtime) {
    case "applying":
      return {
        tone: "nominal",
        text: `r${revision} is active · ${changes}. The runtime is applying it.`,
      };
    case "applied":
      return {
        tone: "nominal",
        text: `r${revision} is active and the runtime has applied it · ${changes}.`,
      };
    case "not_applied":
      return {
        tone: "caution",
        text: `r${revision} is active, but the runtime hasn't applied it yet.${NEEDS_FIX.has(reason ?? "") ? " It needs a fix in Cadence." : ""}`,
      };
    case "none":
      return { tone: "nominal", text: `r${revision} is active · ${changes}.` };
  }
}
