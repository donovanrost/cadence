import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { areaKeys, readinessReader } from "./api.ts";
import { fixLink, orderedFindings, verdictSummary, verdictTitle } from "./present.ts";

const area = (key: string, extra: Record<string, unknown> = {}) => ({
  key,
  status: "ready",
  count: 1,
  unit: "things",
  secondary_count: null,
  secondary_unit: null,
  detail: null,
  ...extra,
});

const finding = (id: string, severity: string, fix: unknown = null) => ({
  id,
  severity,
  cause: id,
  title: `Title ${id}`,
  body: "Body.",
  affected_count: 3,
  fix,
});

const valid = () => ({
  evaluated_at: "2026-11-08T02:41:17Z",
  verdict: { blockers: 1, cautions: 0, stale: 0, not_set_up: 0, optional: 1 },
  areas: areaKeys.map((key) => area(key)),
  findings: [
    finding("optional.default_protocol", "optional", null),
    finding("routing.missing", "blocker", { kind: "profile", id: "type_1", label: null }),
  ],
  recent_changes: null,
});

describe("readinessReader", () => {
  it("decodes the requested shape", () => {
    const result = decode(readinessReader, valid());
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.verdict.blocker).toBe(1);
    expect(result.value.recentChanges).toBeNull();
    expect(result.value.findings[1]?.fix).toEqual({ kind: "profile", id: "type_1", label: null });
  });

  it("rejects areas out of order or missing", () => {
    const body = valid();
    body.areas = [...body.areas].reverse();
    const result = decode(readinessReader, body);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.path).toBe("areas[0].key");

    const short = valid();
    short.areas = short.areas.slice(0, 5);
    expect(decode(readinessReader, short).ok).toBe(false);
  });

  it("rejects a verdict that disagrees with the findings", () => {
    const body = valid();
    body.verdict.blockers = 0;
    expect(decode(readinessReader, body).ok).toBe(false);
  });

  it("requires an id for object fixes and none for list fixes", () => {
    const missingId = valid();
    missingId.findings[1] = finding("x", "blocker", { kind: "station", id: null, label: null });
    expect(decode(readinessReader, missingId).ok).toBe(false);

    const strayId = valid();
    strayId.findings[1] = finding("x", "blocker", { kind: "spacecraft_new", id: "a", label: null });
    expect(decode(readinessReader, strayId).ok).toBe(false);
  });

  it("requires secondary count and unit together", () => {
    const body = valid();
    body.areas[0] = area("fleet", { secondary_count: 2, secondary_unit: null });
    expect(decode(readinessReader, body).ok).toBe(false);
  });

  it("rejects an unknown severity and a negative count", () => {
    const body = valid();
    body.findings[0] = finding("x", "warning");
    expect(decode(readinessReader, body).ok).toBe(false);

    const negative = valid();
    negative.areas[0] = area("fleet", { count: -1 });
    expect(decode(readinessReader, negative).ok).toBe(false);
  });
});

describe("presentation", () => {
  const readiness = () => {
    const result = decode(readinessReader, valid());
    if (!result.ok) throw result.error;
    return result.value;
  };

  it("titles by blockers only and summarizes the rest", () => {
    expect(verdictTitle(readiness())).toBe("1 blocker");
    expect(verdictSummary(readiness())).toBe("1 suggestion");
  });

  it("orders findings blocker first", () => {
    expect(orderedFindings(readiness()).map((f) => f.severity)).toEqual(["blocker", "optional"]);
  });

  it("links a fix to the object that fixes it, honoring a server label", () => {
    expect(fixLink({ kind: "profile", id: "type_1", label: null })).toEqual({
      label: "Open profile",
      to: { name: "setup.profile", params: { profileId: "type_1" } },
    });
    expect(fixLink({ kind: "app", id: "limits", label: "Install" }).label).toBe("Install");
  });
});
