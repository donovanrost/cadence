import {
  actorKinds,
  decoders as d,
  request,
  stationRef,
  type ApiResult,
  type Decoded,
  type MissionId,
  type Reader,
} from "@/api";

/** Contracts: docs/apogee/api/scheduling.md §4: the day's plans (S6), their states and stations. */

export const base = (missionId: MissionId) =>
  `/missions/${encodeURIComponent(missionId)}/contact-plans`;

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
export const planState: Reader<PlanState> = (value, path) => {
  const s = d.string(value, path);
  return planStates.find((candidate) => candidate === s) ?? "unrecognized";
};

/** Station identity joined by the server (Reads.StationRefs); ids/codes are null when unmatched. */
export const stationReader = d.nullable(stationRef);
export type StationRef = Decoded<typeof stationReader>;

/** Why a draft / pending plan was overtaken (DECISIONS: superseded state; scheduling.md). */
export const supersededReader = d.nullable(
  d.object({
    at: d.timestamp,
    by: d.nullable(d.object({ name: d.string })),
    reason: d.knownText(["template_changed", "requirement_changed", "requirement_closed"]),
    changes: d.array(
      d.object({
        kind: d.known(["requirement", "template"]),
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

export const planRow = {
  id: d.token,
  version: d.integer,
  state: planState,
  window: d.object({ from: d.nullable(d.timestamp), to: d.nullable(d.timestamp) }),
  /** `kind: system` = an automatic run ("Cadence"); null only when unknown (api af0279d1). */
  author: d.nullable(
    d.object({
      kind: d.optional(d.knownText(actorKinds)),
      id: d.optional(d.token),
      name: d.string,
    }),
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

export function fetchPlans(
  missionId: MissionId,
  day: string,
  signal?: AbortSignal,
): Promise<ApiResult<PlanList>> {
  return request(
    `${base(missionId)}?day=${encodeURIComponent(day)}`,
    plansReader,
    signal ? { signal } : {},
  );
}

/** Row identity for a station: Cadence id, else the provider ref. */
export const stationKey = (s: StationRef) => s?.id ?? s?.ref ?? "?";
/** Row label: confirmed Cadence code (FAI), else the station name, else the provider ref (ux U25). */
export const stationCode = (s: StationRef) => s?.code ?? s?.name ?? s?.ref ?? "?";
/** Full name for screen readers and tooltips. */
export const stationName = (s: StationRef) => s?.name ?? s?.code ?? s?.ref ?? "unknown station";
