import { describe, expect, it } from "vite-plus/test";
import { decode, type ApiError } from "@/api";
import type { DataSource } from "./api.ts";
import {
  access,
  kindText,
  runsActive,
  runTag,
  sourceFacts,
  sourceFailure,
  tsdbJobs,
  SHARED_LINE,
} from "./present.ts";
import { blankDraft, blockedReason, registerBody } from "./register.ts";
import { sourceRunReader, type SourceDetail, type SourceOptions } from "./writes.ts";

/** Fixtures: api-ops' L11 shapes with fe-setup's 8 changes (agreed 11-13). */
const options: SourceOptions = {
  logical_sources: [{ key: "flight_telemetry", label: "Flight telemetry" }],
  kinds: [
    { key: "byo_tsdb", label: "Your TSDB", requires_credentials: true },
    { key: "managed_tsdb", label: "Managed by Cadence", requires_credentials: false },
  ],
  isolation_levels: {
    byo_tsdb: [{ key: "customer_owned", label: "Customer owned" }],
    managed_tsdb: [{ key: "mission_isolated", label: "This mission only" }],
  },
  storages: [{ key: "questdb", label: "QuestDB" }],
};
const source: DataSource = {
  id: "flight-store",
  display_name: "Flight store",
  kind: "byo_tsdb",
  owner: "customer",
  health: { status: "healthy", checked_at: "2026-11-13T01:00:00Z" },
  last_received_at: null,
  expected_interval_s: null,
  stale: null,
  credentials: null,
  state: "enabled",
  logical_source: { key: "flight_telemetry", label: "Flight telemetry" },
  isolation_level: "customer_owned",
  storage: "questdb",
  credentials_ref: "secret://…/primary",
  shared: false,
  tsdb_actions: undefined,
};
const refused = (code: string, details?: unknown): ApiError => ({
  kind: "conflict",
  code,
  message: "Refused.",
  details: details ?? null,
});

describe("register source (W1)", () => {
  const draft = {
    ...blankDraft,
    name: " Flight store ",
    logical: "flight_telemetry",
    kind: "byo_tsdb" as const,
    isolation: "customer_owned",
    storage: "questdb",
  };
  it("asks for a credentials reference only when the kind needs one", () => {
    expect(blockedReason(draft, options, false)).toBe("This kind needs a credentials reference.");
    expect(blockedReason({ ...draft, kind: "managed_tsdb" }, options, false)).toBeNull();
    expect(blockedReason(blankDraft, options, false)).toBe("Fill in every field.");
  });
  it("sends the trimmed name and the reference", () => {
    expect(registerBody({ ...draft, credentials: " secret://x " }, options)).toEqual({
      display_name: "Flight store",
      logical_source: "flight_telemetry",
      kind: "byo_tsdb",
      isolation_level: "customer_owned",
      storage: "questdb",
      credentials_ref: "secret://x",
    });
    expect(registerBody(draft, options)).toBeNull();
  });
});

describe("source page", () => {
  it("words every D1 kind, including the ones Register doesn't offer", () => {
    expect(kindText("managed_tsdb")).toBe("Managed by Cadence");
    expect(kindText("object_archive")).toBe("Object archive");
    expect(kindText("projection")).toBe("Projection");
  });
  it("keeps shared sources read-only and says why on 403 platform_source", () => {
    expect(access(source, true, false)).toEqual({ editable: true, line: null });
    expect(access({ ...source, shared: true }, true, false)).toEqual({
      editable: false,
      line: SHARED_LINE,
    });
    // A platform admin in admin mode may change a shared source.
    expect(access({ ...source, shared: true }, true, true).editable).toBe(true);
    expect(access(source, false, false)).toEqual({
      editable: false,
      line: "Mission operators change data sources.",
    });
    expect(sourceFailure(refused("platform_source"))).toBe(SHARED_LINE);
  });
  it("words state and binding conflicts", () => {
    expect(sourceFailure(refused("data_source_state", { state: "disabled" }))).toBe(
      "It's already disabled. Reload to see it.",
    );
    expect(sourceFailure(refused("binding_changed", { current_data_source_id: "x" }))).toContain(
      "Someone switched this binding first.",
    );
  });
  it("polls only while a run is queued or running", () => {
    const run = (status: "queued" | "running" | "completed" | "failed") => ({
      job_id: "j",
      kind: "provision" as const,
      status,
      started_at: "2026-11-13T01:00:00Z",
      error: null,
      actions: [],
    });
    const detail = (s: Parameters<typeof run>[0]): SourceDetail => ({
      source,
      bindings: [],
      runs: [run(s)],
    });
    expect(runsActive(detail("running"))).toBe(true);
    expect(runsActive(detail("queued"))).toBe(true);
    expect(runsActive(detail("failed"))).toBe(false);
    expect(runsActive(null)).toBe(false);
  });
  it("reads the L11 facts, and says Not reported before they ship", () => {
    const facts = (s: DataSource) =>
      Object.fromEntries(sourceFacts(s).map((f) => [f.key, f.value]));
    expect(facts(source)).toMatchObject({
      stores: "Flight telemetry",
      isolation: "Customer owned",
      storage: "QuestDB",
      creds: "secret://…/primary",
    });
    // Today's D1 (before L11 ships): the new keys are absent.
    const old = {
      ...source,
      logical_source: undefined,
      isolation_level: undefined,
      storage: undefined,
    };
    expect(facts(old)).toMatchObject({ stores: "Not reported", isolation: "Not reported" });
  });
});

describe("TSDB jobs (api-ops L11 finding 1)", () => {
  it("follow the source's tsdb_actions, and the server's rule when a read lacks them", () => {
    expect(tsdbJobs({ ...source, tsdb_actions: ["provision", "reconcile"] })).toEqual([
      "provision",
      "reconcile",
    ]);
    expect(tsdbJobs({ ...source, tsdb_actions: [] })).toEqual([]);
    expect(
      tsdbJobs({ kind: "byo_tsdb", isolation_level: "mission_isolated", tsdb_actions: undefined }),
    ).toEqual(["provision", "reconcile", "deprovision"]);
    expect(tsdbJobs(source)).toEqual([]);
    expect(
      tsdbJobs({
        kind: "managed_tsdb",
        isolation_level: "mission_isolated",
        tsdb_actions: undefined,
      }),
    ).toEqual([]);
  });
  it("says why a refused job wasn't run", () => {
    expect(sourceFailure(refused("data_source_state", { state: "managed" }))).toBe(
      "This source is managed by Cadence; its storage is provisioned automatically.",
    );
    expect(sourceFailure(refused("data_source_state", { state: "customer_owned" }))).toBe(
      "This source uses your own database as is; Cadence doesn't provision it.",
    );
  });
});

describe("run errors (api-ops L11 C)", () => {
  const run = (error: unknown) => ({
    job_id: "j1",
    kind: "provision",
    status: "failed",
    started_at: "2026-11-14T09:48:52Z",
    error,
  });
  it("reads {code, message}, the old raw string, and none", () => {
    const read = (error: unknown) => {
      const r = decode(sourceRunReader, run(error));
      if (!r.ok) throw r.error;
      return r.value.error;
    };
    expect(
      read({ code: "credentials_unavailable", message: "Its credentials couldn't be read." }),
    ).toEqual({
      code: "credentials_unavailable",
      message: "Its credentials couldn't be read.",
    });
    expect(read({ code: "new_reason", message: "Something new." })).toEqual({
      code: "new_reason",
      message: "Something new.",
    });
    expect(read("{:job_not_running, :failed}")).toEqual({
      code: null,
      message: "{:job_not_running, :failed}",
    });
    expect(read(null)).toBeNull();
    expect(read(undefined)).toBeNull();
  });
});

describe("a run whose outcome is unknown (api-ops jobs fix)", () => {
  it("reads outcome_unknown with its sentence and offers no action", () => {
    const r = decode(sourceRunReader, {
      job_id: "j2",
      kind: "provision",
      status: "outcome_unknown",
      started_at: "2026-11-14T09:48:52Z",
      error: {
        code: "outcome_unknown",
        message:
          "Outcome unknown: this job ran before a fix, and Cadence can't tell whether it succeeded.",
      },
      actions: [],
    });
    if (!r.ok) throw r.error;
    expect(runTag(r.value)).toEqual({ state: "caution", label: "OUTCOME UNKNOWN" });
    expect(r.value.error?.message).toContain("Outcome unknown");
    expect(r.value.actions).toEqual([]);
  });
});
