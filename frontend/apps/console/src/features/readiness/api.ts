import type { MissionId } from "@/api/index.ts";
import { actor, decoders, request, type ApiResult, type Reader } from "@/api/index.ts";

/**
 * Contract (requested): docs/apogee/plans/setup-shapes.md §R, final in docs/apogee/api/setup.md.
 * GET /api/v1/missions/:mission_id/readiness
 */
const { array, integer, known, nullable, object, oneOf, string, timestamp, token } = decoders;

export const areaKeys = ["fleet", "catalog", "comms", "stations", "data_sources", "apps"] as const;
export type AreaKey = (typeof areaKeys)[number];

const areaStatuses = ["ready", "blocker", "caution", "stale", "not_set_up", "unknown"] as const;
export type AreaStatus = (typeof areaStatuses)[number];

export const severities = ["blocker", "caution", "stale", "not_set_up", "optional"] as const;
export type Severity = (typeof severities)[number];

const fixKinds = [
  "spacecraft_list",
  "spacecraft",
  "spacecraft_new",
  "profile",
  "catalog",
  "catalog_import",
  "comms",
  "contact_planning",
  "change_set",
  "station",
  "data_source",
  "app",
] as const;

/** Fix targets that name one object carry its id; list/new targets carry none. */
export type FindingFix =
  | Readonly<{
      kind:
        | "spacecraft_list"
        | "spacecraft_new"
        | "catalog"
        | "catalog_import"
        | "comms"
        | "contact_planning"
        | "change_set";
      label: string | null;
    }>
  | Readonly<{
      kind: "spacecraft" | "profile" | "app";
      id: string;
      label: string | null;
    }>
  /**
   * The list when id is null: domain source_endpoint_ambiguous (no single source to open), and
   * api's stations.no_ground_stations (no station yet; setup.md: id null = the stations list).
   */
  | Readonly<{ kind: "data_source" | "station"; id: string | null; label: string | null }>;

export type ReadinessArea = Readonly<{
  key: AreaKey;
  status: AreaStatus;
  count: number | null;
  unit: string;
  secondary: Readonly<{ count: number; unit: string }> | null;
  detail: string | null;
}>;

export type Finding = Readonly<{
  id: string;
  severity: Severity;
  cause: string;
  title: string;
  body: string;
  affectedCount: number;
  fix: FindingFix | null;
}>;

export type RecentChange = Readonly<{
  at: string;
  kind: string;
  versionLabel: string | null;
  summary: string;
  actorName: string | null;
}>;

export type Readiness = Readonly<{
  evaluatedAt: string;
  verdict: Readonly<Record<Severity, number>>;
  areas: readonly ReadinessArea[];
  findings: readonly Finding[];
  /**
   * null only when the revisions couldn't be read (api setup.md), so R2 says so (U86); `[]` is
   * nothing applied yet. (#313 R2: there's no feed-less case to leave the panel out for.)
   */
  recentChanges: readonly RecentChange[] | null;
}>;

const count: Reader<number> = (value, path = "") => {
  const n = integer(value, path);
  if (n < 0) throw new decoders.DecodeError(path, "non-negative integer");
  return n;
};

const rawFix = object({ kind: known(fixKinds), id: nullable(token), label: nullable(string) });

/**
 * A fix target this console doesn't know yet (the server adds areas over time) reads as "no
 * action" rather than failing the whole page; the finding itself still shows.
 */
const fix: Reader<FindingFix | null> = (value, path = "") => {
  const raw = rawFix(value, path);
  if (raw.kind === "unrecognized") return null;
  switch (raw.kind) {
    case "spacecraft_list":
    case "spacecraft_new":
    case "catalog":
    case "catalog_import":
    case "comms":
    case "contact_planning":
      if (raw.id !== null) throw new decoders.DecodeError(`${path}.id`, "null for a list target");
      return { kind: raw.kind, label: raw.label };
    // #65 catalog_not_converged: any change set touching the spacecraft converges it; an id, if
    // the server ever sends one, isn't needed to get there.
    case "change_set":
      return { kind: raw.kind, label: raw.label };
    case "data_source":
    case "station":
      return { kind: raw.kind, id: raw.id, label: raw.label };
    case "spacecraft":
    case "profile":
    case "app":
      if (raw.id === null) throw new decoders.DecodeError(`${path}.id`, "id for an object target");
      return { kind: raw.kind, id: raw.id, label: raw.label };
  }
};

const rawArea = object({
  key: oneOf(areaKeys),
  status: oneOf(areaStatuses),
  count: nullable(count),
  unit: string,
  secondary_count: nullable(count),
  secondary_unit: nullable(string),
  detail: nullable(string),
});

const area: Reader<ReadinessArea> = (value, path = "") => {
  const raw = rawArea(value, path);
  if ((raw.secondary_count === null) !== (raw.secondary_unit === null))
    throw new decoders.DecodeError(`${path}.secondary_unit`, "set together with secondary_count");
  return {
    key: raw.key,
    status: raw.status,
    count: raw.count,
    unit: raw.unit,
    secondary:
      raw.secondary_count !== null && raw.secondary_unit !== null
        ? { count: raw.secondary_count, unit: raw.secondary_unit }
        : null,
    detail: raw.detail,
  };
};

const finding: Reader<Finding> = (value, path = "") => {
  const raw = object({
    id: token,
    severity: oneOf(severities),
    cause: token,
    title: string,
    body: string,
    affected_count: count,
    fix: (value: unknown, p = "") => (value === null ? null : fix(value, p)),
  })(value, path);
  return {
    id: raw.id,
    severity: raw.severity,
    cause: raw.cause,
    title: raw.title,
    body: raw.body,
    affectedCount: raw.affected_count,
    fix: raw.fix,
  };
};

const recentChange: Reader<RecentChange> = (value, path = "") => {
  const raw = object({
    at: timestamp,
    // free-text: the change's kind, shown as its chip only when there's no version label.
    kind: token,
    version_label: nullable(string),
    summary: string,
    actor: nullable(actor),
  })(value, path);
  return {
    at: raw.at,
    kind: raw.kind,
    versionLabel: raw.version_label,
    summary: raw.summary,
    actorName: raw.actor?.name ?? null,
  };
};

// Keyed by severity (api ships the singular keys; setup-shapes.md §R updated to match).
const verdict = object({
  blocker: count,
  caution: count,
  stale: count,
  not_set_up: count,
  optional: count,
});

export const readinessReader: Reader<Readiness> = (value, path = "") => {
  const raw = object({
    evaluated_at: timestamp,
    verdict,
    areas: array(area, areaKeys.length),
    findings: array(finding, 500),
    recent_changes: nullable(array(recentChange, 50)),
  })(value, path);

  // The six areas arrive in a fixed order; a missing or repeated area would hide a verdict.
  areaKeys.forEach((key, index) => {
    if (raw.areas[index]?.key !== key)
      throw new decoders.DecodeError(`${path ? `${path}.` : ""}areas[${index}].key`, key);
  });

  const tally: Record<Severity, number> = {
    blocker: 0,
    caution: 0,
    stale: 0,
    not_set_up: 0,
    optional: 0,
  };
  for (const item of raw.findings) tally[item.severity] += 1;
  const stated: Record<Severity, number> = raw.verdict;
  for (const severity of severities)
    if (stated[severity] !== tally[severity])
      throw new decoders.DecodeError(
        `${path ? `${path}.` : ""}verdict`,
        `counts matching findings (${severity}: ${tally[severity]})`,
      );

  return {
    evaluatedAt: raw.evaluated_at,
    verdict: tally,
    areas: raw.areas,
    findings: raw.findings,
    recentChanges: raw.recent_changes,
  };
};

export function fetchReadiness(
  missionId: MissionId,
  signal: AbortSignal,
): Promise<ApiResult<Readiness>> {
  return request(`/missions/${encodeURIComponent(missionId)}/readiness`, readinessReader, {
    signal,
  });
}
