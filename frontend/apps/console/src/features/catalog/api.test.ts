import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { catalogIndexReader, revisionSummary } from "./api.ts";

const current = {
  id: "rev-14",
  number: 14,
  label: "FSW 3.1.0",
  declaration_count: 547,
  command_count: null,
  telemetry_count: null,
  spacecraft_count: 500,
};

const body = () => ({
  databases: [{ id: "db-1", name: "Earendil FSW", slug: "earendil-fsw" }],
  database: {
    id: "db-1",
    current_revision: current,
    revisions: [
      {
        id: "rev-14",
        number: 14,
        label: null,
        notes: null,
        artifact: { id: "a", file_name: "fsw.xml", format_label: "XTCE 1.3", size_bytes: null },
        declaration_count: 547,
        spacecraft_count: 500,
        imported_at: "2026-10-14T18:02:00Z",
        actor: null,
      },
    ],
    import_runs: [
      {
        id: "run-1",
        file_name: "fsw.xml",
        format_label: "XTCE 1.3",
        status: "succeeded",
        diagnostic_counts: { error: 0, warning: 2, info: 0 },
        revision_number: 14,
        started_at: "2026-10-14T18:01:00Z",
        completed_at: "2026-10-14T18:02:00Z",
      },
    ],
  },
  permissions: ["catalog.import"],
});

describe("catalogIndexReader", () => {
  it("decodes the index and the null database of an empty mission", () => {
    expect(decode(catalogIndexReader, body()).ok).toBe(true);
    expect(decode(catalogIndexReader, { databases: [], database: null, permissions: [] }).ok).toBe(
      true,
    );
  });

  it("decodes a run that names no file, so one such run can't break the page", () => {
    const b = body();
    const run = b.database.import_runs[0];
    if (run) Object.assign(run, { file_name: null, format_label: null, status: "failed" });
    expect(decode(catalogIndexReader, b).ok).toBe(true);
  });

  it("rejects an unknown import status", () => {
    const b = body();
    const run = b.database.import_runs[0];
    if (run) Object.assign(run, { status: "done" });
    expect(decode(catalogIndexReader, b).ok).toBe(false);
  });

  it("summarizes without per-kind counts it doesn't have", () => {
    expect(revisionSummary(current)).toBe("547 declarations · applied to 500 spacecraft");
    expect(revisionSummary({ ...current, command_count: 212, telemetry_count: 335 })).toBe(
      "547 declarations · 212 commands · 335 telemetry points · applied to 500 spacecraft",
    );
  });
});

describe("groupDiagnostics", () => {
  it("collapses identical diagnostics, errors first", async () => {
    const { groupDiagnostics } = await import("./importRun.ts");
    const warn = { severity: "warning" as const, code: "W1", message: "same", path: null };
    const groups = groupDiagnostics([
      warn,
      warn,
      { severity: "error", code: "E1", message: "bad", path: "a / b" },
      warn,
    ]);
    expect(groups.map((g) => [g.code, g.count])).toEqual([
      ["E1", 1],
      ["W1", 3],
    ]);
    expect(groups[0]?.paths).toEqual(["a / b"]);
  });
});
