import { decoders as d, request, type ApiResult, type Decoded } from "@/api";
import { healthReader, sourceReader, storages, isolationLevels, sourceKinds } from "./api.ts";

/**
 * L11 data-source writes (api-ops' proposal, fe-setup's 8 changes accepted 11-13). They wrap the
 * LiveView's OpsConsole.Actions.DataSources (operate_mission); platform-shared sources answer
 * 403 platform_source. Writes return the source's D1 row so a page replaces it in place.
 */
const base = (missionId: string) => `/missions/${encodeURIComponent(missionId)}`;
const option = <T extends readonly string[]>(keys: T) =>
  d.object({ key: d.known(keys), label: d.string });

/** R1: what Register offers, in the server's words. */
const optionsReader = d.object({
  logical_sources: d.array(d.object({ key: d.token, label: d.string }), 200),
  kinds: d.array(
    d.object({ key: d.known(sourceKinds), label: d.string, requires_credentials: d.boolean }),
    10,
  ),
  isolation_levels: d.object({
    byo_tsdb: d.array(option(isolationLevels), 10),
    managed_tsdb: d.array(option(isolationLevels), 10),
  }),
  storages: d.array(option(storages), 10),
});
export type SourceOptions = Decoded<typeof optionsReader>;
export function fetchSourceOptions(
  missionId: string,
  signal: AbortSignal,
): Promise<ApiResult<SourceOptions>> {
  return request(`${base(missionId)}/data-sources/options`, optionsReader, { signal });
}

export const runStatuses = ["queued", "running", "completed", "failed"] as const;
export const runKinds = ["provision", "reconcile", "deprovision"] as const;
const run = d.object({
  job_id: d.token,
  kind: d.known(runKinds),
  status: d.known(runStatuses),
  inserted_at: d.timestamp,
  // free-text: the job's error message, shown as is.
  error: d.optional(d.nullable(d.string)),
  actions: d.optional(d.array(d.known(["retry", "requeue"] as const), 2)),
});
export type SourceRun = Decoded<typeof run>;

const binding = d.object({
  id: d.token,
  // free-text: a logical source key, an open set R1 lists (the key, not a vocabulary).
  logical_source: d.token,
  data_source_id: d.token,
  status: d.known(["active", "disabled", "superseded"] as const),
});
export type SourceBinding = Decoded<typeof binding>;

/** R2: one source, its bindings, and its newest 20 runs. */
const detailReader = d.object({
  source: sourceReader,
  bindings: d.array(binding, 200),
  runs: d.array(run, 20),
});
export type SourceDetail = Decoded<typeof detailReader>;
export type SourceKey = Readonly<{ missionId: string; sourceId: string }>;
export function fetchSourceDetail(
  k: SourceKey,
  signal: AbortSignal,
): Promise<ApiResult<SourceDetail>> {
  return request(
    `${base(k.missionId)}/data-sources/${encodeURIComponent(k.sourceId)}`,
    detailReader,
    { signal },
  );
}

const sourceOnly = d.object({ source: sourceReader });
const unwrap = async <T>(p: Promise<ApiResult<{ source: T }>>): Promise<ApiResult<T>> => {
  const r = await p;
  return r.ok ? { ok: true, value: r.value.source } : r;
};

export type RegisterBody = Readonly<{
  display_name: string;
  logical_source: string;
  kind: (typeof sourceKinds)[number];
  isolation_level: string;
  storage: string | null;
  credentials_ref?: string;
}>;
/** W1: the server makes the id from the name (unique with -2, -3…). */
export function registerSource(missionId: string, body: RegisterBody) {
  return unwrap(request(`${base(missionId)}/data-sources`, sourceOnly, { method: "POST", body }));
}

/** W2 enable / disable, W5 credential rotation (the reference only). */
export function setSourceEnabled(k: SourceKey, enabled: boolean) {
  const verb = enabled ? "enable" : "disable";
  return unwrap(
    request(
      `${base(k.missionId)}/data-sources/${encodeURIComponent(k.sourceId)}/${verb}`,
      sourceOnly,
      {
        method: "POST",
        body: {},
      },
    ),
  );
}
export function rotateCredential(k: SourceKey, credentialsRef: string) {
  return unwrap(
    request(
      `${base(k.missionId)}/data-sources/${encodeURIComponent(k.sourceId)}/credential`,
      sourceOnly,
      {
        method: "POST",
        body: { credentials_ref: credentialsRef },
      },
    ),
  );
}

/** W4: probe now. */
const probed = d.object({
  source: sourceReader,
  probe: d.object({
    health: healthReader,
    // free-text: the probe's own explanation, shown as is.
    reason: d.nullable(d.string),
  }),
});
export function probeSource(k: SourceKey) {
  return request(
    `${base(k.missionId)}/data-sources/${encodeURIComponent(k.sourceId)}/probe`,
    probed,
    { method: "POST", body: {} },
  );
}

/** W6: start a TSDB job (202); the page polls R2 while it runs. */
const started = d.object({
  source: sourceReader,
  run: d.object({ job_id: d.token, kind: d.known(runKinds), status: d.known(runStatuses) }),
});
export function startTsdbJob(k: SourceKey, kind: (typeof runKinds)[number]) {
  return request(
    `${base(k.missionId)}/data-sources/${encodeURIComponent(k.sourceId)}/tsdb/${kind}`,
    started,
    { method: "POST", body: {} },
  );
}

/** W7: retry a failed run, or requeue one stuck in running. */
export function runAction(missionId: string, jobId: string, action: "retry" | "requeue") {
  return request(
    `${base(missionId)}/data-source-runs/${encodeURIComponent(jobId)}/${action}`,
    d.object({ run }),
    { method: "POST", body: {} },
  );
}

/** W3: switch which source a binding reads; 409 binding_changed if someone switched it first. */
export function switchBinding(
  missionId: string,
  bindingId: string,
  body: Readonly<{ data_source_id: string; expected_data_source_id: string }>,
) {
  return request(
    `${base(missionId)}/data-source-bindings/${encodeURIComponent(bindingId)}`,
    d.object({ binding }),
    { method: "PUT", body },
  );
}
