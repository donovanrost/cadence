import { plural, type OpState } from "@/ui";
import type { CheckResult, Preflight, PreflightCheck, TwoPersonReason } from "./api.ts";

/**
 * Preflight checks → poll rows (Command.md C3, CommandFlow A2). Only checks the server computed
 * appear; a missing check is absent, never green. Sentences name targets by name + SCID.
 */
export const RESULT_STATE: Readonly<Record<CheckResult, OpState>> = {
  go: "nominal",
  hold: "caution",
  no_go: "crit",
};
export const RESULT_WORD: Readonly<Record<CheckResult, string>> = {
  go: "GO",
  hold: "HOLD",
  no_go: "NO-GO",
};

const LABELS: Readonly<Record<string, string>> = {
  identity: "Identity",
  catalog: "Catalog",
  size: "Size",
  conflicts: "Conflicts",
  contact: "Contact",
  two_person: "Two-person",
  changed_since_submit: "Since submit",
};

const IDENTITY_WORDS: Readonly<Record<string, string>> = {
  no_uplink_route: "has no primary uplink route",
  multiple_primary_uplink_routes: "has several primary uplink routes",
  no_source_endpoint: "has no uplink endpoint",
  ambiguous_source_endpoint: "has several uplink endpoints",
  source_endpoint_not_found: "endpoint not found",
  missing_scid: "has no SCID",
};

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
      return r.key.replaceAll("_", " ");
  }
}

function sentence(check: PreflightCheck, pf: Preflight, nameOf: TargetName): string {
  const failed = check.per_target.filter((t) => t.result !== "go");
  const names = failed.map((t) => nameOf(t.spacecraft_id));
  const ev = check.evidence;
  switch (check.key) {
    case "identity": {
      if (check.result === "go") {
        const scids = pf.targets.map((t) => t.scid).filter((s): s is number => s !== null);
        const n = pf.targets.length;
        return `${n === 1 ? "The target resolves" : `All ${n} targets resolve`} · SCID ${list(scids.map(String), 6)}`;
      }
      return failed
        .map(
          (t) =>
            `${nameOf(t.spacecraft_id)} ${typeof t.reason === "string" ? (IDENTITY_WORDS[t.reason] ?? t.reason.replaceAll("_", " ")) : "doesn't resolve"}`,
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
      return check.result === "go"
        ? "Every target has a booked contact"
        : `No booked contact for ${list(names)}: ${names.length === 1 ? "its uplink waits" : "their uplinks wait"} for one`;
    case "two_person":
      return check.result === "go"
        ? "No second GO needed"
        : `Needs a second operator's GO: ${(ev.reasons ?? []).map(reasonWord).join("; ")}`;
    case "changed_since_submit":
      return check.result === "go"
        ? "Same targets, catalog and values as submitted"
        : "Something changed since it was submitted (catalog, targets or values)";
    default:
      return `${words(check.key)}: ${RESULT_WORD[check.result]}`;
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
      key: c.key,
      label: LABELS[c.key] ?? words(c.key),
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
  return (["go", "hold", "no_go"] as const)
    .filter((r) => n(r) > 0)
    .map((r) => `${n(r)} ${RESULT_WORD[r]}`)
    .join(" · ");
}

/** The first NO-GO, in words, for the commit button's reason. */
export function noGoReason(pf: Preflight, nameOf: TargetName): string | null {
  const bad = pf.checks.find((c) => c.result === "no_go");
  return bad ? `${LABELS[bad.key] ?? bad.key} NO-GO: ${sentence(bad, pf, nameOf)}.` : null;
}
