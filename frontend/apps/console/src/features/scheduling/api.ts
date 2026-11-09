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
  /** Requests that never went out, with no live executor: offer Execute (DECISIONS #27, #52). */
  "interrupted",
  /** Placed, but the provider hasn't answered within the window (10 min); no Execute (#52). */
  "unconfirmed",
] as const;
/** `unrecognized`: a state this console doesn't know yet (decoded, never fatal to the read). */
export type PlanState = (typeof planStates)[number] | "unrecognized";
/** A new server state degrades one plan's actions instead of failing every plan read (#52). */
const planState: Reader<PlanState> = (value, path) => {
  const s = d.string(value, path);
  return planStates.find((candidate) => candidate === s) ?? "unrecognized";
};

/** Station identity joined by the server (Reads.StationRefs); ids/codes are null when unmatched. */
export const stationReader = d.nullable(
  d.object({
    ref: d.nullable(d.string),
    id: d.nullable(d.token),
    code: d.nullable(d.string),
    name: d.nullable(d.string),
  }),
);
export type StationRef = Decoded<typeof stationReader>;

/** Why a draft / pending plan was overtaken (DECISIONS: superseded state; scheduling.md). */
export const supersededReader = d.nullable(
  d.object({
    at: d.timestamp,
    by: d.nullable(d.object({ name: d.string })),
    reason: d.string,
    changes: d.array(
      d.object({
        kind: d.string,
        id: d.token,
        name: d.nullable(d.string),
        from_version: d.nullable(d.integer),
        to_version: d.nullable(d.integer),
      }),
      500,
    ),
  }),
);
export type Superseded = NonNullable<Decoded<typeof supersededReader>>;

/** U28: the booked plan a K2 repair proposal repairs, and its repair run. */
const repairOfReader = d.nullable(
  d.object({ plan: d.object({ id: d.token, version: d.integer }), run_id: d.token }),
);

const planRow = {
  id: d.token,
  version: d.integer,
  state: planState,
  window: d.object({ from: d.nullable(d.timestamp), to: d.nullable(d.timestamp) }),
  /** `kind: system` = an automatic run ("Cadence"); null only when unknown (api af0279d1). */
  author: d.nullable(
    d.object({ kind: d.optional(d.string), id: d.optional(d.token), name: d.string }),
  ),
  counts: d.object({
    passes: d.integer,
    minutes: d.integer,
    conflicts: d.integer,
    unsatisfied: d.integer,
  }),
  ready_to_approve: d.boolean,
  updated_at: d.timestamp,
  /** Asked of api (ux); null until the server sends it. */
  created_at: (value: unknown, path?: string) =>
    value === undefined ? null : d.nullable(d.timestamp)(value, path),
  /** Absent on older servers; null when the plan isn't superseded. */
  superseded: (value: unknown, path?: string) =>
    value === undefined ? null : supersededReader(value, path),
  /** U28: set on repair plans (K2's); absent on older servers. */
  repair_of: (value: unknown, path?: string) =>
    value === undefined ? null : repairOfReader(value, path),
};

const planRows = d.array(d.object(planRow), 100);
/** U28: `plans` holds the day's base plans; K2 repair proposals are listed apart (absent on older servers). */
/**
 * ux (api af0279d1): " by Cadence Administrator" for a person, " by Cadence (automatic repair)" for
 * a system run, "" only when the author is unknown. Leading space included, for appending.
 */
export function byAuthor(
  author: PlanSummary["author"],
  automatic: "automatic repair" | "automatic draft" = "automatic repair",
): string {
  if (!author) return "";
  return author.kind === "system" ? ` by ${author.name} (${automatic})` : ` by ${author.name}`;
}

/** ux: K1 names the drafter only when it isn't you (a person other than `userId`, or the system). */
export function draftedByOther(plan: PlanSummary, userId: string): string | null {
  const a = plan.author;
  if (!a || (a.kind !== "system" && a.id === userId)) return null;
  // ux: never put the last change's time next to the creator's name.
  const by = byAuthor(a, "automatic draft");
  const updated = `${plan.updated_at.slice(11, 16)}Z`;
  if (!plan.created_at) return `Drafted${by} · updated ${updated}`;
  const created = `${plan.created_at.slice(11, 16)}Z`;
  return created === updated
    ? `Drafted ${created}${by}`
    : `Drafted ${created}${by} · updated ${updated}`;
}

export const plansReader = d.object({
  plans: planRows,
  repair_proposals: (value: unknown, path?: string) =>
    value === undefined ? [] : planRows(value, path),
});
export type PlanSummary = Decoded<typeof plansReader>["plans"][number];
export type PlanList = Decoded<typeof plansReader>;

/** One conflict / at-risk entry; fields depend on `code`, so the code-specific ones are optional. */
const planIssue = d.object({
  code: d.string,
  snapshot_ids: d.array(d.token),
  spacecraft_id: d.optional(d.nullable(d.token)),
  ground_station_id: d.optional(d.token),
  window_id: d.optional(d.token),
  kind: d.optional(d.string),
});

const planRef = d.object({ id: d.token, version: d.integer });

const unconfirmedReader = d.nullable(
  d.object({
    window_ms: d.integer,
    booked: d.integer,
    passes: d.array(
      d.object({
        snapshot_id: d.token,
        provider: d.object({ id: d.token, name: d.nullable(d.string) }),
        sent_at: d.timestamp,
      }),
      5_000,
    ),
  }),
);

export const planDetailReader = d.object({
  ...planRow,
  passes: d.array(
    d.object({
      snapshot_id: d.token,
      spacecraft_id: d.nullable(d.token),
      station: stationReader,
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
        window: d.object({ from: d.nullable(d.timestamp), to: d.nullable(d.timestamp) }),
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
  /** `selected_contacts_overlap` (spacecraft_id) or `station_unavailable` (station window, U26). Both block. */
  conflicts: d.array(planIssue, 5_000),
  /** `station_degraded`: passes inside a degraded window; a warning only (U26). */
  at_risk: (value: unknown, path?: string) =>
    value === undefined ? [] : d.array(planIssue, 5_000)(value, path),
  /** qa #30: the day's repair chain, root first then each applied repair; null on older servers. */
  chain: (value: unknown, path?: string) =>
    value === undefined ? null : d.array(planRef, 100)(value, path),
  /**
   * qa #30: the id of the plan a new Re-plan starts from (latest applied repair, else the root).
   * The server sends a bare id; an `{id, version}` object is accepted too (the doc doesn't say).
   */
  chain_head: (value: unknown, path?: string): string | null => {
    if (value === undefined || value === null) return null;
    return typeof value === "string" ? d.token(value, path) : planRef(value, path).id;
  },
  /** U30 (api b122f667): placed bookings unanswered past the window, on any state; else null. */
  unconfirmed: (value: unknown, path?: string) =>
    value === undefined ? null : unconfirmedReader(value, path),
});
export type PlanDetail = Decoded<typeof planDetailReader>;
export type PlanIssue = PlanDetail["conflicts"][number];
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
): Promise<ApiResult<PlanList>> {
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
      station: stationReader,
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
  station: stationReader,
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
      /** #56: lost passes a live single booking already covers (sent nothing); absent → []. */
      covered: (value: unknown, path?: string) =>
        value === undefined
          ? []
          : d.array(
              d.object({
                snapshot_id: d.token,
                spacecraft_id: d.nullable(d.token),
                station: stationReader,
                starts_at: d.timestamp,
                ends_at: d.timestamp,
                covered_by: d.token,
              }),
              5_000,
            )(value, path),
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

/**
 * S8: start a repair run off the request; progress via scheduling_progress {kind: "draft"}.
 * `window` (ISO-8601) narrows the repair; without it the server uses now → the plan's horizon end,
 * which can exceed the policy's repair window (422 fleet_repair_horizon_exceeded).
 */
export function startRepair(
  missionId: string,
  planId: string,
  operationId: string,
  window?: Readonly<{ from: string; to: string }>,
) {
  return request(`${base(missionId)}/${encodeURIComponent(planId)}/repairs`, startReader, {
    method: "POST",
    body: { operation_id: operationId, ...(window ? { from: window.from, to: window.to } : {}) },
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

/** One row per window: the same provider window can come back once per requirement (ux K1 #5). */
export function distinctWindows(list: readonly Alternative[]): Alternative[] {
  const seen = new Set<string>();
  return list.filter((a) => {
    const key = `${stationKey(a.station)}|${a.starts_at}|${a.ends_at}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

/** Row identity for a station: Cadence id, else the provider ref. */
export const stationKey = (s: StationRef) => s?.id ?? s?.ref ?? "?";
/** Row label: confirmed Cadence code (FAI), else the station name, else the provider ref (ux U25). */
export const stationCode = (s: StationRef) => s?.code ?? s?.name ?? s?.ref ?? "?";
/** Full name for screen readers and tooltips. */
export const stationName = (s: StationRef) => s?.name ?? s?.code ?? s?.ref ?? "unknown station";

const availabilityWindow = d.object({
  id: d.token,
  ground_station_id: d.token,
  kind: d.oneOf(["outage", "maintenance", "degraded"]),
  from: d.timestamp,
  to: d.nullable(d.timestamp),
  eta: d.nullable(d.timestamp),
  source: d.string,
  reported_at: d.nullable(d.timestamp),
  reason: d.nullable(d.string),
  cleared_at: d.nullable(d.timestamp),
});
export const availabilityReader = d.object({
  at: d.timestamp,
  stations: d.array(
    d.object({
      ground_station_id: d.token,
      state: d.oneOf(["up", "degraded", "down"]),
      since: d.nullable(d.timestamp),
      eta: d.nullable(d.timestamp),
      basis: d.nullable(d.string),
      windows: d.array(availabilityWindow, 500),
    }),
    500,
  ),
});
export type Availability = Decoded<typeof availabilityReader>;
export type AvailabilityWindow = Decoded<typeof availabilityWindow>;

/** S7: every station's reported state with active and upcoming windows (7 d). 'up' = nothing reported. */
export function fetchAvailability(
  missionId: string,
  signal?: AbortSignal,
): Promise<ApiResult<Availability>> {
  return request(
    `/missions/${encodeURIComponent(missionId)}/station-availability`,
    availabilityReader,
    signal ? { signal } : {},
  );
}
