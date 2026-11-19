import {
  isKeyOf,
  decoders as d,
  request,
  type ApiResult,
  type Decoded,
  type MissionId,
  type Reader,
} from "@/api";
import { startEstimateReader } from "./start-limit.ts";
import { base } from "./plans-api.ts";
import { planDetailReader } from "./plan-detail-api.ts";

/** Contracts: docs/apogee/api/scheduling.md §4: drafting a day's plan (S3), its setup and demand. */

export const runStates = [
  "queued",
  "running",
  "completed",
  "partial",
  "failed",
  "canceled",
  "interrupted",
] as const;
export type RunState = (typeof runStates)[number];

/** `failure` is an opaque server document; only `code` / `message` are read when present. */
const failure: Reader<{ code: string | null; message: string | null } | null> = (value) => {
  if (value === null || value === undefined || typeof value !== "object" || Array.isArray(value))
    return null;
  const pick = (k: string) => {
    const v: unknown = Reflect.get(value, k);
    return typeof v === "string" ? v : null;
  };
  return { code: pick("code"), message: pick("message") };
};

/** Drafting phases in order (ScheduleFlow K1: MATERIALIZING → SEARCHING → OPTIMIZING → PLAN). */
export const runPhases = [
  "materializing",
  "searching",
  "optimizing",
  "materializing_plan",
] as const;
export type RunPhase = (typeof runPhases)[number] | Readonly<{ unrecognized: string }>;
/** The phase in words; an unknown one shows the server's word (typing §12). */
export const runPhaseText = (p: RunPhase): string =>
  (typeof p === "string" ? p : p.unrecognized).replaceAll("_", " ");

export const draftRunReader = d.object({
  id: d.token,
  state: d.oneOf(runStates),
  phase: d.nullable(d.knownText(runPhases)),
  horizon: d.object({ from: d.timestamp, to: d.timestamp }),
  failure,
  started_at: d.nullable(d.timestamp),
  updated_at: d.timestamp,
  /** api 413c8e18: completion time; for an interrupted run the last recorded progress. */
  stopped_at: (value: unknown, path?: string) =>
    value === undefined ? null : d.nullable(d.timestamp)(value, path),
});

export const draftReader = d.object({
  run: draftRunReader,
  plan: d.nullable(planDetailReader),
});
export type Draft = Decoded<typeof draftReader>;

export const startReader = d.object({
  run_id: d.token,
  outcome: d.oneOf(["created", "replayed"]),
  state: d.known(runStates),
});

export function fetchDraft(
  missionId: MissionId,
  runId: string,
  signal?: AbortSignal,
): Promise<ApiResult<Draft>> {
  return request(
    `${base(missionId)}/drafts/${encodeURIComponent(runId)}`,
    draftReader,
    signal ? { signal } : {},
  );
}

/** S3: 202 with the run; the same operation_id replays the same run on any node. */
export function startDraft(missionId: MissionId, day: string, operationId: string) {
  return request(`${base(missionId)}/drafts`, startReader, {
    method: "POST",
    body: { day, operation_id: operationId },
  });
}

export function continueDraft(missionId: MissionId, runId: string) {
  return request(
    `${base(missionId)}/drafts/${encodeURIComponent(runId)}/continue`,
    d.object({ run_id: d.token, state: d.known(runStates) }),
    {
      method: "POST",
      body: {},
    },
  );
}

/** Why a requirement went unmet (S2 demand), keyed by the codes the console words (rule A). */
const REASONS = {
  outside_requirement_window: "No window inside the required time",
  direction_not_executable: "No window supports the required direction",
  provider_unavailable: "Provider reports no availability",
  opportunity_expired: "The window expired",
  minimum_duration_not_met: "Windows are shorter than the minimum duration",
  provider_not_allowed: "The rule excludes this provider",
  station_not_allowed: "The rule excludes this station",
  estimated_volume_unknown: "Expected volume unknown",
  estimated_volume_unavailable: "Expected volume not reported",
  preferred_duration_not_met: "Shorter than the preferred duration",
  // #74 (domain 1cf19879); provisional words until ux rules.
  max_gap_exceeded: "A gap between contacts is longer than the rule allows",
} as const;

/** Plain words for a reason code; unknown codes are shown as words, never dropped. */
export function reasonText(code: string): string {
  return isKeyOf(REASONS, code)
    ? REASONS[code]
    : code.replaceAll("_", " ").replace(/^\w/, (c) => c.toUpperCase());
}

export const setupReader = d.object({
  setup: d.object({
    ready: d.boolean,
    missing: d.array(d.string),
    policy: d.nullable(d.object({ id: d.token, version: d.integer })),
    requirements: d.integer,
    templates: d.integer,
    /** U52 (api 6af9e279d): the day's template fan-out; null when no active template counts. */
    template_requirements_estimate: d.optional(d.nullable(startEstimateReader)),
  }),
});
export type PlanningSetup = Decoded<typeof setupReader>["setup"];

export const dayDemandReader = d.object({
  day: d.string,
  spacecraft_with_rules: d.integer,
  contacts_needed: d.integer,
  without_rule: d.integer,
  spacecraft_total: d.integer,
});
export type DayDemand = Decoded<typeof dayDemandReader>;

/** U52: `day` (UTC YYYY-MM-DD) is the day Start would draft; the estimate counts that day. */
export function fetchSetup(
  missionId: MissionId,
  day: string,
  signal?: AbortSignal,
): Promise<ApiResult<{ setup: PlanningSetup }>> {
  const q = new URLSearchParams({ day }).toString();
  return request(`${base(missionId)}/setup?${q}`, setupReader, signal ? { signal } : {});
}

export function fetchDayDemand(
  missionId: MissionId,
  day: string,
  signal?: AbortSignal,
): Promise<ApiResult<DayDemand>> {
  return request(
    `${base(missionId)}/demand?day=${encodeURIComponent(day)}`,
    dayDemandReader,
    signal ? { signal } : {},
  );
}
