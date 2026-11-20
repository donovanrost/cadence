import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { compositionReader, type Composition } from "@/features/catalog/composition.ts";
import { preflightReader, type Preflight } from "./api.ts";
import { checkLabel, checkRows, holdReason } from "./checks.ts";
import {
  compositionName,
  craftList,
  decisionLine,
  holdOneLine,
  holdPlaceholder,
  holdSeveralLine,
} from "./withdrawn.ts";

/** U109 (E2, #546, readers first): the Composition HOLD and the shared words. */
const layer = (n: number, mount = "/") => ({
  layer_id: `layer-${n}`,
  mount,
  catalog_revision: { id: `rev-${n}`, number: n, database: { id: "db-1", name: "Earendil" } },
});
const comp = (layers: unknown[], number: number | null = 3): Composition => {
  const r = decode(compositionReader, {
    composition_id: "comp-1",
    number,
    imported_layers: layers,
    created_by: null,
    created_at: "2026-11-20T09:00:00Z",
  });
  if (!r.ok) throw r.error;
  return r.value;
};
const ana = { id: "u-ana", name: "Ana R." };
const at = "2026-11-20T09:12:00Z";

describe("compositionName (U109)", () => {
  it("composition N with several catalogs, catalog rev N with one, else this composition", () => {
    expect(compositionName(comp([layer(4), layer(9, "/power")]))).toBe("composition 3");
    expect(compositionName(comp([layer(4), layer(9, "/power")], null))).toBe("this composition");
    expect(compositionName(comp([layer(4)]))).toBe("catalog rev 4");
    expect(compositionName(null, { number: 7 })).toBe("catalog rev 7");
    expect(compositionName(null)).toBe("this composition");
    expect(compositionName(undefined, null)).toBe("this composition");
  });
});

describe("the Composition HOLD's lines (U109)", () => {
  const one = (x: Parameters<typeof holdOneLine>[2]) =>
    holdOneLine("EARENDIL-004", "composition 3", x);
  it("names the decider and quotes the reason, withdrawn or rejected", () => {
    expect(one({ kind: "withdrawn", decided_by: ana, decided_at: at, reason: "Bad limits." })).toBe(
      "EARENDIL-004 is on composition 3, whose approval Ana R. withdrew at 11-20 09:12Z: “Bad limits”. Acknowledge the HOLD to send this request to EARENDIL-004 anyway.",
    );
    expect(one({ kind: "rejected", decided_by: ana, decided_at: at, reason: "Bad limits" })).toBe(
      "EARENDIL-004 is on composition 3, which Ana R. rejected at 11-20 09:12Z: “Bad limits”. Acknowledge the HOLD to send this request to EARENDIL-004 anyway.",
    );
  });

  it("drops the name it doesn't have, and ends at the time with no reason", () => {
    expect(one({ kind: "withdrawn", decided_by: null, decided_at: at, reason: null })).toBe(
      "EARENDIL-004 is on composition 3, whose approval was withdrawn at 11-20 09:12Z. Acknowledge the HOLD to send this request to EARENDIL-004 anyway.",
    );
    expect(
      one({ kind: "rejected", decided_by: { id: null, name: null }, decided_at: at, reason: " " }),
    ).toBe(
      "EARENDIL-004 is on composition 3, which was rejected at 11-20 09:12Z. Acknowledge the HOLD to send this request to EARENDIL-004 anyway.",
    );
  });

  it("a decision kind it doesn't know reads neutrally, never as withdrawn (ca-ux on #632)", () => {
    // As the reader decodes it: knownText gives an unknown kind as { unrecognized }.
    const x = {
      kind: { unrecognized: "suspended" },
      decided_by: null,
      decided_at: at,
      reason: "x",
    };
    expect(one(x)).toBe(
      "EARENDIL-004 is on composition 3, which is no longer approved since 11-20 09:12Z. Acknowledge the HOLD to send this request to EARENDIL-004 anyway.",
    );
    expect(decisionLine(x)).toBe("No longer approved since 11-20 09:12Z.");
  });

  it("counts several targets, three names then 'and N more'", () => {
    expect(holdSeveralLine(["EARENDIL-004", "EARENDIL-007", "EARENDIL-011"], 12)).toBe(
      "3 of the 12 targets are on a composition that's no longer approved: EARENDIL-004, EARENDIL-007 and EARENDIL-011. Acknowledge the HOLD to send this request to them anyway.",
    );
    expect(craftList(["A", "B", "C", "D", "E"])).toBe("A, B, C and 2 more");
    expect(holdPlaceholder(1)).toBe("Why it's safe to command it");
    expect(holdPlaceholder(3)).toBe("Why it's safe to command them");
  });
});

const target = (i: number) => ({
  index: i,
  spacecraft_id: `sc-${i}`,
  source_endpoint_id: null,
  name: `EARENDIL-00${i}`,
  scid: i,
  failure: null,
});
const preflight = (checks: unknown[], targets = [target(4)]): Preflight => {
  const r = decode(preflightReader, {
    valid: true,
    digest: "d",
    members: targets.length,
    second_go_required: false,
    targets,
    checks,
  });
  if (!r.ok) throw r.error;
  return r.value;
};
const held = (i: number, extra: Record<string, unknown> = {}) => ({
  spacecraft_id: `sc-${i}`,
  result: "hold",
  reason: "model_approval_withdrawn",
  revision_id: "rev-4",
  kind: "withdrawn",
  decided_by: ana,
  decided_at: at,
  reason_text: "Bad limits",
  composition: null,
  ...extra,
});
const check = (per_target: unknown[]) => ({
  key: "model_approval_withdrawn",
  result: "hold",
  per_target,
  evidence: {},
  ackable: true,
  hold_basis: "b1",
});
const nameOf = (id: string) => `EARENDIL-00${id.slice(3)}`;

describe("the Composition check (#546 readers first)", () => {
  it("reads a held target's decision, labels the check by key and words the row", () => {
    const pf = preflight([check([held(4, { composition: comp([layer(4)]) })])]);
    const [row] = checkRows(pf, nameOf);
    expect(checkLabel("model_approval_withdrawn")).toBe("Composition");
    expect(row).toMatchObject({ key: "model_approval_withdrawn", label: "Composition" });
    expect(row?.sentence).toBe(
      "EARENDIL-004 is on catalog rev 4, whose approval Ana R. withdrew at 11-20 09:12Z: “Bad limits”. Acknowledge the HOLD to send this request to EARENDIL-004 anyway.",
    );
    expect(holdReason(pf, {}, nameOf)).toBe(
      "Acknowledge the Composition HOLD with a note, or clear it.",
    );
  });

  it("several held targets read as a count; GO says every target is approved", () => {
    const pf = preflight(
      [check([held(4), held(7), { spacecraft_id: "sc-9", result: "go" }])],
      [target(4), target(7), target(9)],
    );
    expect(checkRows(pf, nameOf)[0]?.sentence).toBe(
      "2 of the 3 targets are on a composition that's no longer approved: EARENDIL-004 and EARENDIL-007. Acknowledge the HOLD to send this request to them anyway.",
    );
    const go = preflight([{ ...check([]), result: "go", ackable: null, hold_basis: null }]);
    // U109 (#634): a catalog revision until the check says a target is composed (D4).
    expect(checkRows(go, nameOf)[0]?.sentence).toBe(
      "Every target is on an approved catalog revision",
    );
    const composed = preflight([
      {
        ...check([]),
        result: "go",
        ackable: null,
        hold_basis: null,
        evidence: { composed: true },
      },
    ]);
    expect(checkRows(composed, nameOf)[0]?.sentence).toBe(
      "Every target is on an approved composition",
    );
  });

  it("today's per_target, without #546's keys, still reads", () => {
    const pf = preflight([
      {
        key: "contact",
        result: "go",
        per_target: [{ spacecraft_id: "sc-4", result: "go" }],
        evidence: {},
      },
    ]);
    expect(pf.checks[0]?.per_target[0]?.composition).toBeUndefined();
  });
});
