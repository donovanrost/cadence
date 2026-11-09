import { decoders as d, request, type ApiResult, type Decoded, type Reader } from "@/api";

/** Contracts: docs/apogee/api/scheduling.md §4 (S3 drafts, S6 plans, plan detail with S2 demand). */
const base = (missionId: string) => `/missions/${encodeURIComponent(missionId)}/contact-plans`;

export const planStates = [
  "draft",
  "pending_approval",
  "approved",
  "executing",
  "partially_reserved",
  "reserved",
  "failed",
  "canceled",
  "superseded",
  /** executing with no live executor (cluster-wide): offer Execute (DECISIONS #27). */
  "interrupted",
] as const;
export type PlanState = (typeof planStates)[number];

const planRow = {
  id: d.token,
  version: d.integer,
  state: d.oneOf(planStates),
  window: d.object({ from: d.nullable(d.timestamp), to: d.nullable(d.timestamp) }),
  author: d.nullable(d.object({ name: d.string })),
  counts: d.object({
    passes: d.integer,
    minutes: d.integer,
    conflicts: d.integer,
    unsatisfied: d.integer,
  }),
  ready_to_approve: d.boolean,
  updated_at: d.timestamp,
};

export const plansReader = d.object({ plans: d.array(d.object(planRow), 100) });
export type PlanSummary = Decoded<typeof plansReader>["plans"][number];

export const planDetailReader = d.object({
  ...planRow,
  passes: d.array(
    d.object({
      snapshot_id: d.token,
      spacecraft_id: d.nullable(d.token),
      station: d.nullable(d.string),
      starts_at: d.timestamp,
      ends_at: d.timestamp,
      synthetic: d.boolean,
      locked: d.boolean,
    }),
    5_000,
  ),
  demand: d.object({
    rule_met: d.integer,
    rule_total: d.integer,
    spacecraft: d.array(
      d.object({
        spacecraft_id: d.token,
        rule_met: d.boolean,
        contacts: d.object({ have: d.integer, need: d.nullable(d.integer) }),
        reasons: d.array(d.string),
      }),
      5_000,
    ),
    rules: d.array(
      d.object({
        requirement_id: d.token,
        version: d.integer,
        spacecraft_id: d.nullable(d.token),
        text: d.string,
        source: d.string,
      }),
      5_000,
    ),
  }),
  unmet: d.array(
    d.object({
      requirement_id: d.token,
      requirement_version: d.integer,
      spacecraft_id: d.nullable(d.token),
      why: d.array(d.string),
    }),
    5_000,
  ),
  conflicts: d.array(
    d.object({
      code: d.string,
      spacecraft_id: d.nullable(d.token),
      snapshot_ids: d.array(d.token),
    }),
    5_000,
  ),
});
export type PlanDetail = Decoded<typeof planDetailReader>;
export type PlanPass = PlanDetail["passes"][number];

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

const draftRunReader = d.object({
  id: d.token,
  state: d.oneOf(runStates),
  phase: d.nullable(d.string),
  horizon: d.object({ from: d.timestamp, to: d.timestamp }),
  failure,
  started_at: d.nullable(d.timestamp),
  updated_at: d.timestamp,
});

export const draftReader = d.object({
  run: draftRunReader,
  plan: d.nullable(planDetailReader),
});
export type Draft = Decoded<typeof draftReader>;

const startReader = d.object({
  run_id: d.token,
  outcome: d.oneOf(["created", "replayed"]),
  state: d.string,
});

export function fetchPlans(
  missionId: string,
  day: string,
  signal?: AbortSignal,
): Promise<ApiResult<{ plans: readonly PlanSummary[] }>> {
  return request(
    `${base(missionId)}?day=${encodeURIComponent(day)}`,
    plansReader,
    signal ? { signal } : {},
  );
}

export function fetchPlan(
  missionId: string,
  planId: string,
  signal?: AbortSignal,
): Promise<ApiResult<PlanDetail>> {
  return request(
    `${base(missionId)}/${encodeURIComponent(planId)}`,
    planDetailReader,
    signal ? { signal } : {},
  );
}

export function fetchDraft(
  missionId: string,
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
export function startDraft(missionId: string, day: string, operationId: string) {
  return request(`${base(missionId)}/drafts`, startReader, {
    method: "POST",
    body: { day, operation_id: operationId },
  });
}

export function continueDraft(missionId: string, runId: string) {
  return request(
    `${base(missionId)}/drafts/${encodeURIComponent(runId)}/continue`,
    d.object({ run_id: d.token, state: d.string }),
    {
      method: "POST",
      body: {},
    },
  );
}

const REASONS: Readonly<Record<string, string>> = {
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
};

/** Plain words for a reason code; unknown codes are shown as words, never dropped. */
export function reasonText(code: string): string {
  return REASONS[code] ?? code.replaceAll("_", " ").replace(/^\w/, (c) => c.toUpperCase());
}

export const setupReader = d.object({
  setup: d.object({
    ready: d.boolean,
    missing: d.array(d.string),
    policy: d.nullable(d.object({ id: d.token, version: d.integer })),
    requirements: d.integer,
    templates: d.integer,
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

export function fetchSetup(
  missionId: string,
  signal?: AbortSignal,
): Promise<ApiResult<{ setup: PlanningSetup }>> {
  return request(`${base(missionId)}/setup`, setupReader, signal ? { signal } : {});
}

export function fetchDayDemand(
  missionId: string,
  day: string,
  signal?: AbortSignal,
): Promise<ApiResult<DayDemand>> {
  return request(
    `${base(missionId)}/demand?day=${encodeURIComponent(day)}`,
    dayDemandReader,
    signal ? { signal } : {},
  );
}

export type Acknowledgement = Readonly<{ requirement_id: string; reason: string }>;

const submitReader = d.object({
  plan_id: d.token,
  state: d.string,
  outcome: d.oneOf(["pending_approval", "executing", "replayed"]),
});
export type SubmitResult = Decoded<typeof submitReader>;

/** S5. Member → pending_approval; org admin → approve + execute off the request (202). */
export function submitPlan(
  missionId: string,
  plan: Readonly<{ id: string; version: number }>,
  operationId: string,
  acknowledgements: readonly Acknowledgement[],
): Promise<ApiResult<SubmitResult>> {
  return request(`${base(missionId)}/${encodeURIComponent(plan.id)}/submit`, submitReader, {
    method: "POST",
    body: {
      expected_version: plan.version,
      operation_id: operationId,
      ...(acknowledgements.length > 0 ? { acknowledgements } : {}),
    },
  });
}

/** Resume an interrupted (or approved, never started) execution; items are idempotent. */
export function executePlan(missionId: string, planId: string) {
  return request(
    `${base(missionId)}/${encodeURIComponent(planId)}/execute`,
    d.object({ plan_id: d.token, state: d.string }),
    {
      method: "POST",
      body: {},
    },
  );
}

/** Acknowledgement reasons must be 10–2000 characters (scheduling.md S5). */
export const REASON_MIN = 10;
export const REASON_MAX = 2000;

/** S4 edit: next plan version with the selection changed; returns the new plan detail. */
export function editPlan(
  missionId: string,
  plan: Readonly<{ id: string; version: number }>,
  change: Readonly<{ add?: readonly string[]; remove?: readonly string[] }>,
): Promise<ApiResult<PlanDetail>> {
  return request(`${base(missionId)}/${encodeURIComponent(plan.id)}/versions`, planDetailReader, {
    method: "POST",
    body: { expected_version: plan.version, ...change },
  });
}

export const alternativesReader = d.object({
  plan_id: d.token,
  version: d.integer,
  spacecraft_id: d.token,
  rule_met: d.boolean,
  contacts: d.object({ have: d.integer, need: d.nullable(d.integer) }),
  alternatives: d.array(
    d.object({
      snapshot_id: d.token,
      requirement_id: d.nullable(d.token),
      station: d.nullable(d.string),
      starts_at: d.timestamp,
      ends_at: d.timestamp,
      synthetic: d.boolean,
      effect: d.object({
        rule_met_after: d.boolean,
        contacts_after: d.object({ have: d.integer, need: d.nullable(d.integer) }),
        clashes_with: d.array(d.token),
      }),
    }),
    2_000,
  ),
});
export type Alternatives = Decoded<typeof alternativesReader>;
export type Alternative = Alternatives["alternatives"][number];

/** S4: unselected opportunities for one spacecraft with their effect (nothing is written). */
export function fetchAlternatives(
  missionId: string,
  planId: string,
  spacecraftId: string,
  signal?: AbortSignal,
): Promise<ApiResult<Alternatives>> {
  return request(
    `${base(missionId)}/${encodeURIComponent(planId)}/alternatives?spacecraft_id=${encodeURIComponent(spacecraftId)}`,
    alternativesReader,
    signal ? { signal } : {},
  );
}

/** Plans whose selection can still change (editing a plan in review returns it to draft). */
export const editableStates: readonly PlanState[] = ["draft", "pending_approval"];

const repairPass = d.object({
  snapshot_id: d.token,
  spacecraft_id: d.nullable(d.token),
  station: d.nullable(d.string),
  starts_at: d.timestamp,
  ends_at: d.timestamp,
});

export const repairReader = d.object({
  run: draftRunReader,
  plan: d.nullable(planDetailReader),
  source_plan: d.object({ id: d.token, version: d.integer }),
  diff: d.nullable(
    d.object({
      kept: d.array(repairPass, 5_000),
      moved: d.array(
        d.object({
          spacecraft_id: d.nullable(d.token),
          from: repairPass,
          to: repairPass,
          offset_s: d.integer,
        }),
        5_000,
      ),
      dropped: d.array(repairPass, 5_000),
      added: d.array(repairPass, 5_000),
      totals: (value: unknown) => value,
    }),
  ),
});
export type Repair = Decoded<typeof repairReader>;

/** States a plan must be in to be repaired (scheduling.md S8). */
export const repairableStates: readonly PlanState[] = [
  "executing",
  "partially_reserved",
  "failed",
  "interrupted",
];

/** S8: start a repair run off the request; progress via scheduling_progress {kind: "draft"}. */
export function startRepair(missionId: string, planId: string, operationId: string) {
  return request(`${base(missionId)}/${encodeURIComponent(planId)}/repairs`, startReader, {
    method: "POST",
    body: { operation_id: operationId },
  });
}

export function fetchRepair(
  missionId: string,
  runId: string,
  signal?: AbortSignal,
): Promise<ApiResult<Repair>> {
  return request(
    `${base(missionId)}/repairs/${encodeURIComponent(runId)}`,
    repairReader,
    signal ? { signal } : {},
  );
}
