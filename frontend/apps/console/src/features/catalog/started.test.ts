import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { catalogIndexReader, startedLine } from "./api.ts";

const row = (requested_by?: unknown) => ({
  id: "run-1",
  file_name: "fsw.xml",
  format_label: "XTCE 1.3",
  status: "succeeded",
  diagnostic_counts: { error: 0, warning: 0, info: 0 },
  revision_number: 14,
  started_at: "2026-11-19T05:40:00Z",
  completed_at: "2026-11-19T05:41:00Z",
  ...(requested_by === undefined ? {} : { requested_by }),
});

/** Decodes one run row through the index reader, as the Import runs table gets it. */
function started(requested_by?: unknown): string {
  const r = decode(catalogIndexReader, {
    databases: [],
    database: {
      id: "db-1",
      current_revision: null,
      revisions: [],
      import_runs: [row(requested_by)],
    },
    permissions: [],
  });
  if (!r.ok) throw new Error(r.error.message);
  const run = r.value.database?.import_runs[0];
  if (!run) throw new Error("no run");
  return startedLine(run);
}

describe("startedLine (U103's Started cell, #146's requested_by)", () => {
  it("names a person the server names, and Cadence itself", () => {
    expect(started({ kind: "user", name: "Mira K." })).toBe("11-19 05:40Z by Mira K.");
    expect(started({ kind: "system", name: "Earendil seed" })).toBe("11-19 05:40Z by Cadence");
  });

  it("marks a service as one, named or not (#370, #372)", () => {
    expect(started({ kind: "service", name: "Nightly planner" })).toBe(
      "11-19 05:40Z by Nightly planner (a service identity)",
    );
    expect(started({ kind: "service", name: null })).toBe("11-19 05:40Z by a service identity");
  });

  it("shows the time alone for an unnamed person, an unknown kind or no record", () => {
    expect(started({ kind: "user", name: null })).toBe("11-19 05:40Z");
    expect(started({ kind: "robot", name: "R2" })).toBe("11-19 05:40Z");
    expect(started(null)).toBe("11-19 05:40Z");
    expect(started()).toBe("11-19 05:40Z");
  });
});
