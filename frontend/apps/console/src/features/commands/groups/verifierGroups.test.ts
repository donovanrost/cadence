import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { preflightReader } from "./api.ts";
import { perPoint, pointCaption, seriesReader } from "./series.ts";
import {
  groupMeta,
  groupsAt,
  groupVerifierText,
  revisionsText,
  spanText,
  targetRevisions,
  verifiersDiffer,
} from "./verifierGroups.ts";

const v = (id: string, name: string, phase: string, timeout_ms: number | null) => ({
  id,
  name,
  phase,
  timeout_ms,
  delay_ms: null,
  description: null,
  severity: "critical",
});
const rev = (n: number) => ({ number: n, label: `Revision ${n}` });
const target = (i: number, id: string, revision: ReturnType<typeof rev> | null) => ({
  index: i,
  spacecraft_id: id,
  source_endpoint_id: null,
  name: id.toUpperCase(),
  scid: i + 1,
  failure: null,
  catalog_revision: revision,
});
const many = Array.from({ length: 499 }, (_, i) => `sc-${i + 2}`);

/** Tonight's case (api's U51 example): SET_MODE verifies differently on EARENDIL-001. */
const preflight = (
  commands: unknown,
  targets = [target(0, "sc-1", rev(4)), target(1, "sc-2", rev(3))],
) => {
  const r = decode(preflightReader, {
    valid: true,
    digest: "d",
    members: 2,
    second_go_required: false,
    targets,
    checks: [],
    commands,
  });
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
};
const tonight = [
  {
    position: 0,
    command_id: "cmd-set-mode",
    verifier_groups: [
      {
        verifiers: [
          v("v1", "Uplink started", "acceptance", 10_000),
          v("v2", "Accepted on board", "start", 30_000),
        ],
        catalog_revisions: [rev(3)],
        spacecraft_ids: many,
      },
      {
        verifiers: [
          v("v3", "Uplink started", "acceptance", 10_000),
          v("v4", "Accepted on board", "start", 30_000),
          v("v5", "Mode applied", "completion", 60_000),
        ],
        catalog_revisions: [rev(4)],
        spacecraft_ids: ["sc-1"],
      },
    ],
  },
];
const nameOf = (id: string) => (id === "sc-1" ? "EARENDIL-001" : id.toUpperCase());

describe("U51 when targets differ", () => {
  it("rows list each group's whole verifier set, then the longest wait, then targets and revision", () => {
    const groups = groupsAt(preflight(tonight), 0);
    expect(verifiersDiffer(groups)).toBe(true);
    const [big, one] = groups;
    if (!big || !one) throw new Error("two groups");
    expect(groupVerifierText(big).text).toBe("Uplink started · Accepted on board · within 30 s");
    expect(groupMeta(big, nameOf)).toBe("499 targets · rev 3");
    expect(groupVerifierText(one).text).toBe(
      "Uplink started · Accepted on board · Mode applied · within 60 s",
    );
    expect(groupMeta(one, nameOf)).toBe("EARENDIL-001 · rev 4");
  });

  it("an empty set reads 'No verifier'; one group is no difference; missing commands read none", () => {
    const groups = groupsAt(
      preflight([
        {
          position: 0,
          command_id: "c",
          verifier_groups: [
            { verifiers: [], catalog_revisions: [rev(12)], spacecraft_ids: ["sc-1"] },
          ],
        },
      ]),
      0,
    );
    expect(verifiersDiffer(groups)).toBe(false);
    expect(
      groupVerifierText(groups[0] ?? { verifiers: [], catalog_revisions: [], spacecraft_ids: [] }),
    ).toEqual({
      text: "No verifier: can't turn green",
      verifiable: false,
    });
    expect(groupsAt(preflight(undefined), 0)).toEqual([]);
  });

  it("names targets' revisions only when they span more than one", () => {
    const spanning = preflight(tonight);
    expect(targetRevisions(spanning)?.get("sc-1")).toBe("rev 4");
    expect(spanText(spanning)).toBe("rev 3 · 4");
    const same = preflight(tonight, [target(0, "sc-1", rev(4)), target(1, "sc-2", rev(4))]);
    expect(targetRevisions(same)).toBeNull();
    expect(spanText(same)).toBeNull();
    expect(revisionsText([{ number: null, label: "Draft" }, rev(15), rev(14), rev(15)])).toBe(
      "rev 14 · 15 · Draft",
    );
  });

  it("an unresolved target's revision is null (it's already a Catalog NO-GO)", () => {
    const p = preflight(tonight, [target(0, "sc-1", rev(4)), target(1, "sc-2", null)]);
    expect(p.targets[1]?.catalog_revision).toBeNull();
    expect(targetRevisions(p)).toBeNull();
  });
});

describe("U51 U2: one plot per verifier point", () => {
  const series = (points: unknown) => {
    const r = decode(seriesReader, {
      verifier: null,
      point: null,
      commanded: null,
      band: null,
      window: null,
      targets: [],
      target_count: 500,
      truncated: false,
      summary: { met: 0, not_met: 0, pending: 0 },
      points,
    });
    if (!r.ok) throw new Error(r.error.message);
    return r.value;
  };
  const mode = {
    point_id: "HK.sc_mode",
    name: "sc_mode",
    verifier_name: "Mode applied",
    position: 0,
    spacecraft_ids: ["sc-1"],
  };
  const accepted = {
    ...mode,
    point_id: "HK.cmd_count",
    verifier_name: "Accepted on board",
    spacecraft_ids: many,
  };

  it("plots per point only when there's more than one, captioned with its targets", () => {
    expect(perPoint(series(undefined))).toBe(false);
    expect(perPoint(series([mode]))).toBe(false);
    const s = series([accepted, mode]);
    expect(perPoint(s)).toBe(true);
    const [a, m] = s.points ?? [];
    if (!a || !m) throw new Error("two points");
    expect(pointCaption(a, nameOf)).toBe("Accepted on board · 499 targets");
    expect(pointCaption(m, nameOf)).toBe("Mode applied · EARENDIL-001");
  });
});
