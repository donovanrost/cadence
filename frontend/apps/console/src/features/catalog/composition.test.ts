import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import {
  actorInSentence,
  compositionInSentence,
  compositionReader,
  compositionTitle,
  isComposed,
  madeOfLine,
  type Composition,
} from "./composition.ts";
import { modelRevisionReader } from "./approval/api.ts";
import {
  cannotDecideLine,
  composedByLine,
  composedImportersLine,
  revisionWord,
} from "./approval/words.ts";

/** #538 (D2c; U109): the composition's words, readers first. */
const layer = (id: string, mount: string, db: string | null, n: number | null) => ({
  layer_id: id,
  mount,
  catalog_revision:
    n === null ? null : { id: `cr-${id}`, number: n, database: { id: `db-${id}`, name: db } },
});
const comp = (
  layers: unknown[],
  number: number | null = 3,
  created_by: unknown = null,
): Composition => {
  const r = decode(compositionReader, {
    composition_id: "mission_model_composition:abc",
    number,
    imported_layers: layers,
    created_by,
    created_at: "2026-11-20T09:12:00Z",
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
};

describe("naming and Made of", () => {
  it("is composed only with more than one catalog; one catalog reads as today", () => {
    expect(isComposed(comp([layer("a", "/", "Bus", 4)]))).toBe(false);
    expect(
      isComposed(comp([layer("a", "/", "Bus", 4), layer("b", "/payload", "Payload", 2)])),
    ).toBe(true);
    expect(isComposed(null)).toBe(false);
  });

  it("names it by number, or 'this composition'; never an id", () => {
    const c = comp([layer("a", "/", "Bus", 4), layer("b", "/payload", "Payload", 2)]);
    expect(compositionInSentence(c)).toBe("composition 3");
    expect(compositionTitle(c)).toBe("Composition 3");
    const none = comp([layer("a", "/", "Bus", 4), layer("b", "/payload", "Payload", 2)], null);
    expect(compositionInSentence(none)).toBe("this composition");
    expect(compositionTitle(none)).toBeNull();
  });

  it("says Made of by database name, adds the place only to tell two apart, never at '/'", () => {
    expect(
      madeOfLine(comp([layer("a", "/", "Bus", 4), layer("b", "/payload", "Payload", 2)])),
    ).toBe("Made of: Bus catalog rev 4 · Payload catalog rev 2");
    expect(madeOfLine(comp([layer("a", "/bus", "EPS", 4), layer("b", "/payload", "EPS", 2)]))).toBe(
      "Made of: EPS catalog rev 4 (bus) · EPS catalog rev 2 (payload)",
    );
    expect(
      madeOfLine(comp([layer("a", "/", "Bus", 4), layer("b", "/a/payload", null, null)])),
    ).toBe("Made of: Bus catalog rev 4 · an imported catalog (payload)");
    const five = comp(["a", "b", "c", "d", "e"].map((x) => layer(x, `/${x}`, x.toUpperCase(), 1)));
    expect(madeOfLine(five)).toBe(
      "Made of: A catalog rev 1 · B catalog rev 1 · C catalog rev 1 and 2 more",
    );
    expect(madeOfLine(five, true)).toContain("E catalog rev 1");
  });

  it("names actors as U103: a service marked, Cadence run by someone", () => {
    expect(actorInSentence({ kind: "user", id: "u1", name: "Owen P.", run_by: undefined })).toBe(
      "Owen P.",
    );
    expect(
      actorInSentence({ kind: "service", id: "s1", name: "Nightly planner", run_by: undefined }),
    ).toBe("Nightly planner (a service identity)");
    expect(
      actorInSentence({
        kind: "system",
        id: "x",
        name: null,
        run_by: { id: "u2", name: "Mira K." },
      }),
    ).toBe("Cadence, run by Mira K.");
    expect(
      actorInSentence({ kind: "system", id: "x", name: null, run_by: { id: null, name: null } }),
    ).toBe("Cadence, run by a person");
    expect(actorInSentence({ kind: "user", id: null, name: null, run_by: undefined })).toBeNull();
  });
});

describe("the approval page for a composed base", () => {
  const base = {
    id: "mm-1",
    status: "candidate",
    imported_at: null,
    imported_by: null,
    catalog_revision: null,
    decision: null,
    viewer_can_decide: false,
    affected_groups: null,
    affected_groups_count: null,
    viewer_is_importer: false,
    cannot_decide_because: null,
    plans_ready: true,
    comparison: null,
  };
  const twoLayers = {
    composition_id: "mission_model_composition:abc",
    number: 3,
    imported_layers: [layer("a", "/", "Bus", 4), layer("b", "/payload", "Payload", 2)],
    created_by: { kind: "user", id: "u9", name: "Owen P." },
    created_at: "2026-11-20T09:12:00Z",
  };
  const read = (extra: Record<string, unknown>) => {
    const r = decode(modelRevisionReader, { ...base, composition: twoLayers, ...extra });
    if (!r.ok) throw new Error(JSON.stringify(r.error));
    return r.value;
  };

  it("names the decision 'composition 3' and the one-catalog page as before", () => {
    expect(revisionWord(read({}))).toBe("composition 3");
    const one = decode(modelRevisionReader, {
      ...base,
      catalog_revision: { id: "cr", number: 4, label: null, database_id: "db" },
    });
    if (!one.ok) throw new Error("decode");
    expect(revisionWord(one.value)).toBe("rev 4");
  });

  it("says the composer and self-approval lines, with a service when there is one", () => {
    expect(cannotDecideLine(read({ cannot_decide_because: "composer" }))).toBe(
      "You chose this combination of catalogs, so another org admin approves composition 3.",
    );
    expect(
      cannotDecideLine(
        read({
          cannot_decide_because: "self_approval",
          cannot_decide_details: { via_service: { id: "s1", name: "Nightly planner" } },
        }),
      ),
    ).toBe(
      "Nightly planner, a service identity you're accountable for, imported one of its catalogs, so another org admin approves composition 3.",
    );
  });

  it("words a nameless service in U100's form, with no commas (#609 review)", () => {
    const nameless = { via_service: { id: "s1", name: null } };
    expect(
      cannotDecideLine(
        read({ cannot_decide_because: "composer", cannot_decide_details: nameless }),
      ),
    ).toBe(
      "A service identity you're accountable for chose this combination of catalogs, so another org admin approves composition 3.",
    );
    expect(
      cannotDecideLine(
        read({ cannot_decide_because: "self_approval", cannot_decide_details: nameless }),
      ),
    ).toBe(
      "A service identity you're accountable for imported one of its catalogs, so another org admin approves composition 3.",
    );
  });

  it("says who composed it and who imported each catalog, dropping the unnamed", () => {
    const r = read({
      importers: [
        { layer_id: "a", importers: [{ kind: "user", id: "u1", name: "Mira K." }] },
        { layer_id: "b", importers: [{ kind: "user", id: null, name: null }] },
      ],
    });
    expect(composedImportersLine(r)).toBe("Imported by Mira K. (Bus catalog rev 4).");
    if (!r.composition) throw new Error("no composition");
    expect(composedByLine(r.composition)).toMatch(/^Composed by Owen P\. at /);
    expect(composedByLine({ ...r.composition, created_by: null })).toBeNull();
  });
});
