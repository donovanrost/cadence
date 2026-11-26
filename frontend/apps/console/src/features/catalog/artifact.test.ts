import { describe, expect, it } from "vite-plus/test";
import type { ApiError } from "@/api";
import { artifactLine, reimportFailure, runningRun, type ArtifactPage } from "./artifact.ts";

/** Fixtures: api setup.md "Source files" (05aa7e399). */
const artifact: ArtifactPage["artifact"] = {
  id: "art_1",
  file_name: "earendil.xtce.xml",
  format_label: "XTCE",
  format_version: "1.2",
  media_type: "application/xml",
  size_bytes: 2_400_000,
  sha256: "ab".repeat(32),
  uploaded_at: "2026-11-12T14:03:00Z",
  uploaded_by: { kind: "user" as const, id: null, name: "Mira K." },
  database: { id: "db1", name: "Flight" },
  download_url: "/api/v1/missions/m/catalog/artifacts/art_1/download",
};

describe("catalog source file (L18)", () => {
  it("says format, size and who uploaded it", () => {
    expect(artifactLine(artifact)).toMatch(/^XTCE 1\.2 · .+ · uploaded 11-12.* by Mira K\.$/);
    expect(
      artifactLine({ ...artifact, format_version: null, size_bytes: null, uploaded_by: null }),
    ).toMatch(/^XTCE · uploaded 11-12/);
  });

  it("opens the run already on this file from a 409", () => {
    const running: ApiError = {
      kind: "conflict",
      code: "import_running",
      message: "Refused.",
      details: { import_run_id: "run_7" },
    };
    expect(runningRun(running)).toBe("run_7");
    expect(reimportFailure(running)).toBe("An import of this file is already running.");
  });
});
