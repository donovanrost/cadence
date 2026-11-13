import { describe, expect, it } from "vite-plus/test";
import type { ApiError } from "@/api";
import type { DataSource } from "./api.ts";
import { access, runsActive, sourceFacts, sourceFailure, SHARED_LINE } from "./present.ts";
import { blankDraft, blockedReason, registerBody } from "./register.ts";
import type { SourceDetail, SourceOptions } from "./writes.ts";

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
      inserted_at: "2026-11-13T01:00:00Z",
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
