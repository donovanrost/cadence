import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { importRunRow } from "./api.ts";
import { importRunReader, sameDatabaseMatch } from "./importRun.ts";
import RolloutBreaking from "./RolloutBreaking.vue";
import {
  matchTag,
  matchVerdict,
  noOwnRevision,
  otherDatabaseVerdict,
  resultText,
  sameAsTag,
} from "./matchedWords.ts";

/** #119 · ux U99: an import whose content matched a revision that already exists. */

const bus = { id: "db-bus", name: "Bus catalog" };
const match = (o: Record<string, unknown> = {}) => ({
  model_revision_id: "mission_model_revision:abc",
  revision: { id: "cr-4", number: 4, label: "FSW 2.4", database: bus },
  status: "candidate",
  decision: null,
  cannot_approve: null,
  ...o,
});
const approvedBy = (name: string | null) => ({
  kind: "approved",
  by: { name },
  at: "2026-11-15T09:12:00Z",
  reason: null,
});
const run = (o: Record<string, unknown> = {}) => ({
  id: "run-9",
  status: "succeeded",
  started_at: "2026-11-19T10:00:00Z",
  completed_at: "2026-11-19T10:00:04Z",
  file: { name: "bus.yaml", format_label: "Cadence YAML", size_bytes: 100 },
  failure_reason: null,
  declaration_count: 3,
  diagnostics: [],
  revision: null,
  base_revision: null,
  diff: null,
  ...o,
});
const readRun = (o: Record<string, unknown> = {}) => {
  const r = decode(importRunReader, run(o));
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
};
const readMatch = (o: Record<string, unknown> = {}) => {
  const m = readRun({ matched_revision: match(o) }).matched_revision;
  if (!m) throw new Error("no match decoded");
  return m;
};

describe("the C3 reader (matched_revision is additive)", () => {
  it("reads a run with no key, a null key and a full match", () => {
    expect(readRun().matched_revision).toBeUndefined();
    expect(readRun({ matched_revision: null }).matched_revision).toBeNull();
    expect(readMatch().model_revision_id).toBe("mission_model_revision:abc");
  });

  it("keeps an unknown status or reason as unrecognized, never failing the read", () => {
    expect(readMatch({ status: "archived" }).status).toEqual({ unrecognized: "archived" });
    const ca = { reason: "quorum", via_service: null, service: null };
    expect(readMatch({ cannot_approve: ca }).cannot_approve?.reason).toEqual({
      unrecognized: "quorum",
    });
  });

  it("tells the four combinations of own revision and match apart", () => {
    const own = { id: "cr-1", number: 1, label: null, database: { id: "db-p", name: "Payload" } };
    expect(sameDatabaseMatch(readRun({ matched_revision: match() }))).not.toBeNull();
    expect(sameDatabaseMatch(readRun({ revision: own, matched_revision: match() }))).toBeNull();
    expect(sameDatabaseMatch(readRun({ revision: own }))).toBeNull();
    expect(sameDatabaseMatch(readRun())).toBeNull();
  });
});

describe("U99 words, same database", () => {
  it("approved: who and when, both or neither", () => {
    expect(matchVerdict(readMatch({ status: "approved", decision: approvedBy("Ana R.") }))).toEqual(
      {
        tone: "info",
        text: "This file matches catalog rev 4, so no new revision was created. Rev 4 was approved by Ana R. at 11-15 09:12Z.",
        rollout: true,
      },
    );
    expect(matchVerdict(readMatch({ status: "approved", decision: approvedBy(null) })).text).toBe(
      "This file matches catalog rev 4, so no new revision was created. Rev 4 was approved at 11-15 09:12Z.",
    );
    expect(matchVerdict(readMatch({ status: "approved" })).text).toContain("Rev 4 was approved.");
  });

  it("waiting, with each separation sentence from the server's one answer", () => {
    const line = (cannot_approve: unknown) =>
      matchVerdict(readMatch({ cannot_approve })).text.replace(
        "This file matches catalog rev 4, so no new revision was created. Rev 4 is waiting for approval in Setup › Catalog.",
        "",
      );
    const svc = (name: string | null) => ({ id: "svc-1", name });
    expect(line(null)).toBe("");
    expect(line({ reason: "self", via_service: null, service: null })).toBe(
      " Because you imported this content, another org admin has to approve rev 4.",
    );
    expect(line({ reason: "self", via_service: svc("Nightly planner"), service: null })).toBe(
      " Because Nightly planner, a service identity you're accountable for, imported this content, another org admin has to approve rev 4.",
    );
    expect(line({ reason: "self", via_service: svc(null), service: null })).not.toContain("svc-1");
    expect(line({ reason: "authors_unknown", via_service: null, service: svc(null) })).toBe(
      " Rev 4 can't be approved yet: the service identity that imported it has no one recorded as accountable for it. An org admin records who's accountable in People › Service identities.",
    );
    expect(line({ reason: "authors_unknown", via_service: null, service: null })).toContain(
      "Rev 4 can't be approved: Cadence can't tell who imported it",
    );
    expect(line({ reason: "quorum", via_service: null, service: null })).toBe(
      " You can't approve rev 4, so another org admin has to.",
    );
  });

  it("rejected quotes the reason as text; unknown and retired give the first sentence only", () => {
    const rejected = readMatch({
      status: "rejected",
      decision: { ...approvedBy("Ana R."), kind: "rejected", reason: "<b>Wrong</b> FSW build." },
    });
    expect(matchVerdict(rejected).text).toBe(
      "This file matches catalog rev 4, which was rejected by Ana R. at 11-15 09:12Z: “<b>Wrong</b> FSW build.” No new revision was created. To try again, correct the catalog and import the corrected file. It becomes a new revision.",
    );
    for (const status of ["retired", "archived"])
      expect(matchVerdict(readMatch({ status }))).toEqual({
        tone: "info",
        text: "This file matches catalog rev 4, so no new revision was created.",
        rollout: false,
      });
  });

  it("reads the unnumbered case as U65 does", () => {
    const m = readMatch({
      revision: null,
      cannot_approve: { reason: "self", via_service: null, service: null },
    });
    expect(matchVerdict(m).text).toBe(
      "This file matches a catalog revision that already exists, so no new revision was created. This catalog revision is waiting for approval in Setup › Catalog. Because you imported this content, another org admin has to approve this catalog revision.",
    );
    expect(resultText(m)).toBe("matched existing · candidate");
  });
});

describe("U99 words, another catalog database", () => {
  const own = { number: 1, database: { id: "db-p", name: "Payload catalog" } };
  it("names both revisions, and a database with no name never by its id", () => {
    const m = readMatch({ status: "approved", decision: approvedBy("Ana R.") });
    expect(otherDatabaseVerdict(own, m).text).toBe(
      "Imported as catalog rev 1 of Payload catalog. Its content is the same as catalog rev 4 of Bus catalog, approved by Ana R. at 11-15 09:12Z, so rev 1 is approved too.",
    );
    const nameless = readMatch({
      revision: { ...match().revision, database: { id: "db-x", name: null } },
    });
    expect(otherDatabaseVerdict(own, nameless).text).toBe(
      "Imported as catalog rev 1 of Payload catalog. Its content is the same as catalog rev 4 in another catalog of this mission, which is waiting for approval. One approval covers both.",
    );
    expect(otherDatabaseVerdict(own, readMatch({ status: "archived" })).text).toBe(
      "Imported as catalog rev 1 of Payload catalog. Its content is the same as catalog rev 4 of Bus catalog.",
    );
  });
});

describe("the runs table and the source-file page", () => {
  const row = (matched: unknown, revision_number: number | null) => {
    const r = decode(importRunRow, {
      id: "run-9",
      file_name: "bus.yaml",
      status: "succeeded",
      diagnostic_counts: { error: 0, warning: 0, info: 0 },
      revision_number,
      started_at: "2026-11-19T10:00:00Z",
      completed_at: null,
      matched,
    });
    if (!r.ok) throw new Error(r.error.message);
    return r.value;
  };
  const got = (r: ReturnType<typeof row>) => {
    if (!r.matched) throw new Error("no match decoded");
    return r.matched;
  };
  const m = (o: Record<string, unknown> = {}) => ({
    number: 4,
    status: "candidate",
    model_revision_id: "mission_model_revision:abc",
    first: { number: 4, database: bus },
    ...o,
  });

  it("tags a same-database match, rejected and unnumbered forms included", () => {
    const tag = (o: Record<string, unknown>) => matchTag(got(row(m(o), null)));
    expect(matchTag(got(row(m(), null)))).toEqual({ label: "Matches rev 4", state: "neutral" });
    expect(tag({ status: "rejected" })).toEqual({
      label: "Matches rejected rev 4",
      state: "caution",
    });
    expect(tag({ number: null }).label).toBe("Matches an existing revision");
    expect(tag({ number: null, status: "rejected" }).label).toBe("Matches a rejected revision");
  });

  it("adds Same as for another database's match; none when first is null", () => {
    expect(sameAsTag(got(row(m(), 1)))?.label).toBe("Same as Bus catalog rev 4");
    const nameless = m({ first: { number: 4, database: { id: "db-x", name: null } } });
    expect(sameAsTag(got(row(nameless, 1)))?.label).toBe("Same as a revision in another catalog");
    expect(sameAsTag(got(row(m({ first: null }), 1)))).toBeNull();
    expect(row(undefined, 1).matched).toBeUndefined();
  });

  it("says a matched file made no revision of its own", () => {
    expect(noOwnRevision(got(row(m(), null)))).toEqual({
      headline: "This file made no revision of its own",
      sentence: "Its content matches catalog rev 4.",
    });
    expect(noOwnRevision(got(row(m({ number: null }), null))).sentence).toBe(
      "Its content matches a catalog revision that already exists.",
    );
  });
});

describe("the rollout words touched by #119", () => {
  it("an unknown breaking count asks for the diff to be checked, never shows 0", () => {
    const w = mount(RolloutBreaking, {
      props: { revisionNumber: 4, breaking: null, modelValue: false },
    });
    expect(w.text()).toContain(
      "This page can't show whether rev 4 breaks anything in use. Check its import's diff before you stage.",
    );
    expect(w.text()).toContain("I've checked rev 4's diff");
    expect(w.text()).not.toContain("0");
  });
});
