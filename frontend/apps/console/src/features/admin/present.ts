import { formatHourMinute, formatRelative } from "@/ui";
import type { RuntimeRow } from "./api.ts";

/** Words for the admin area (ux screens/Admin.md); runtime in U38's words. */

type Reason = NonNullable<NonNullable<RuntimeRow["runtime"]>["reason"]>;
/** U38/U91: retrying can't clear spec_mismatch / reconcile_crashed: faults in Cadence. */
const reasonWords: Readonly<Record<Reason, string>> = {
  apply_failed: "applying the configuration failed",
  spec_mismatch: "it needs a fix in Cadence",
  reconcile_crashed: "it needs a fix in Cadence",
  runtime_not_running: "the runtime isn't running",
  unrecognized: "the reason isn't known to the console",
};

/** `■ APPLIED gen 8` / `◆ NOT APPLIED since 23:10Z: <reason>` / `Not known on this node` (U13). */
export function runtimeText(r: RuntimeRow["runtime"]): Readonly<{
  state: "nominal" | "crit" | "stale";
  text: string;
}> {
  if (!r) return { state: "stale", text: "Not known on this node" };
  switch (r.state) {
    case "applied":
      return {
        state: "nominal",
        text: r.applied_generation !== null ? `APPLIED gen ${r.applied_generation}` : "APPLIED",
      };
    case "not_applied": {
      const since = r.since ? ` since ${formatHourMinute(new Date(r.since))}` : "";
      return {
        state: "crit",
        text: `NOT APPLIED${since}${r.reason ? `: ${reasonWords[r.reason]}` : ""}`,
      };
    }
    case "unrecognized":
      return { state: "stale", text: "State not known to the console" };
  }
}

const rank = (r: RuntimeRow) =>
  !r.runtime
    ? 1
    : r.runtime.state === "not_applied"
      ? 0
      : r.runtime.state === "unrecognized"
        ? 1
        : 2;

/** Worst first (spec), then by organization and mission name. */
export const worstFirst = (rows: readonly RuntimeRow[]) =>
  [...rows].sort(
    (a, b) =>
      rank(a) - rank(b) ||
      a.organization.name.localeCompare(b.organization.name) ||
      a.mission.name.localeCompare(b.mission.name),
  );

/** Telemetry last received as an age; `—` with the reason when unknown (U13, never zero). */
export const telemetryText = (at: string | null, now: Date) =>
  at ? formatRelative(new Date(at), now) : "— not known on this node";

/** `acme-space` from `Acme Space`: the sheet fills the slug from the name; the server re-checks. */
export const slugOf = (name: string) =>
  name
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 120);

/** `Created Acme Space. Invitation sent to ana@acme.space.` and the honest variants (U20). */
export function createdText(r: {
  organization: { name: string };
  invitation: { email: string; delivery: "submitted" | "unavailable" | "unrecognized" } | null;
  invitation_error: string | null;
}): Readonly<{ tone: "nominal" | "caution"; text: string }> {
  const made = `Created ${r.organization.name}.`;
  if (!r.invitation)
    return {
      tone: "caution",
      text: `${made} The invitation wasn't sent: ${r.invitation_error ?? "no reason given"}.`,
    };
  if (r.invitation.delivery === "submitted")
    return { tone: "nominal", text: `${made} Invitation sent to ${r.invitation.email}.` };
  return {
    tone: "caution",
    text: `Created ${r.organization.name}, but no email went out. Share the invitation link from its page.`,
  };
}
