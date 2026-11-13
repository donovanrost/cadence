import { decoders as d, detailsOf, isError, type ApiError } from "@/api";
import { failureOutcome } from "@/features/changes/index.ts";
import { formatDuration, formatShort, type OpState } from "@/ui";
import type { DataSource } from "./api.ts";
import type { SourceDetail, SourceRun } from "./writes.ts";

/** "Managed by Cadence" / "Your TSDB"; the server's key when it's a kind this console doesn't know. */
export function kindText(kind: DataSource["kind"]): string {
  switch (kind) {
    case "managed_tsdb":
      return "Managed by Cadence";
    case "byo_tsdb":
      return "Your TSDB";
    case "unrecognized":
      return "Other";
  }
}

export const SHARED_LINE = "Shared by the platform. Platform admins change it in admin mode.";

/**
 * Who may write (api-ops L11): `data_sources.manage`, and for a platform-shared source also a
 * platform admin in admin mode (403 platform_source otherwise). `line` says why it's read-only.
 */
export function access(
  s: DataSource,
  canManage: boolean,
  adminMode: boolean,
): { editable: boolean; line: string | null } {
  if (s.shared === true && !adminMode) return { editable: false, line: SHARED_LINE };
  if (!canManage) return { editable: false, line: "Mission operators change data sources." };
  return { editable: true, line: null };
}

export function enabledTag(s: DataSource): { state: OpState; label: string } | null {
  if (s.state === undefined || s.state === "unrecognized") return null;
  return s.state === "enabled"
    ? { state: "nominal", label: "ENABLED" }
    : { state: "off", label: "DISABLED" };
}

const RUN_WORDS: Readonly<Record<SourceRun["status"], { state: OpState; label: string }>> = {
  queued: { state: "neutral", label: "QUEUED" },
  running: { state: "live", label: "RUNNING" },
  completed: { state: "nominal", label: "DONE" },
  failed: { state: "crit", label: "FAILED" },
  unrecognized: { state: "neutral", label: "UNKNOWN" },
};
export const runTag = (r: SourceRun) => RUN_WORDS[r.status];

const KIND_WORDS: Readonly<Record<SourceRun["kind"], string>> = {
  provision: "Provision",
  reconcile: "Reconcile",
  deprovision: "Deprovision",
  unrecognized: "Job",
};
export const runKindText = (r: SourceRun) => KIND_WORDS[r.kind];

/** api-ops: poll R2 about every 5 s while a run is queued or running. */
export const runsActive = (detail: SourceDetail | null) =>
  detail?.runs.some((r) => r.status === "queued" || r.status === "running") ?? false;

export const ACTION_LINES = {
  retry: "Retry starts a failed run again.",
  requeue: "Requeue puts a run that's stuck in running back in the queue.",
} as const;

/** One sentence for a refused write (U20). */
export function sourceFailure(error: ApiError): string {
  if (isError(error, "platform_source")) return SHARED_LINE;
  if (isError(error, "data_source_state")) {
    const state = detailsOf(
      error,
      d.object({ state: d.known(["enabled", "disabled"] as const) }),
    )?.state;
    return state === "enabled" || state === "disabled"
      ? `It's already ${state}. Reload to see it.`
      : "Its state changed. Reload to see it.";
  }
  if (isError(error, "binding_changed"))
    return "Someone switched this binding first. Reload to see where it reads from now.";
  return failureOutcome(error, "changed").sentence;
}

export function freshness(s: DataSource): { state: OpState; text: string } {
  if (s.last_received_at === null) return { state: "off", text: "Nothing received yet" };
  const at = formatShort(new Date(s.last_received_at));
  if (s.stale === true)
    return {
      state: "stale",
      text: `Late · last ${at}${s.expected_interval_s ? `, expected every ${formatDuration(s.expected_interval_s)}` : ""}`,
    };
  if (s.stale === false) return { state: "nominal", text: `Fresh · last ${at}` };
  return { state: "neutral", text: `Last ${at}` };
}

export function health(s: DataSource): { state: OpState; text: string } {
  if (s.health === null || s.health.status === "unknown")
    return { state: "off", text: "Not reported" };
  return s.health.status === "healthy"
    ? { state: "nominal", text: "Healthy" }
    : { state: "caution", text: "Degraded" };
}

const ISOLATION_WORDS: Readonly<Record<NonNullable<DataSource["isolation_level"]>, string>> = {
  shared: "Shared across organizations",
  customer_owned: "Customer owned",
  org_isolated: "This organization only",
  mission_isolated: "This mission only",
  unrecognized: "Other",
};
const STORAGE_WORDS: Readonly<Record<NonNullable<DataSource["storage"]>, string>> = {
  questdb: "QuestDB",
  postgres_projection: "Postgres projection",
  unrecognized: "Other",
};

/** The source page's facts (L11 additions read "Not reported" until api-ops ships them). */
/** An ApKeyValue item (declared here: the lint's type checker can't see types inside .vue). */
export type Fact = Readonly<{ key: string; label: string; value: string; mono?: boolean }>;
export function sourceFacts(s: DataSource): Fact[] {
  return [
    { key: "stores", label: "Stores", value: s.logical_source?.label ?? "Not reported" },
    {
      key: "isolation",
      label: "Isolation",
      value: s.isolation_level ? ISOLATION_WORDS[s.isolation_level] : "Not reported",
    },
    {
      key: "storage",
      label: "Storage",
      value: s.storage ? STORAGE_WORDS[s.storage] : "Not reported",
    },
    { key: "fresh", label: "Freshness", value: freshness(s).text },
    { key: "health", label: "Health", value: health(s).text },
    { key: "creds", label: "Credentials", value: s.credentials_ref ?? "None", mono: true },
  ];
}
