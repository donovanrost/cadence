import { describe, expect, it, vi } from "vite-plus/test";
import type { CommandDetail } from "../api.ts";
import { missionId as missionIdReader, decode } from "@/api/index.ts";
import {
  changedBy,
  draftReplyReader,
  isBlank,
  restoreDraft,
  toDocument,
  type ComposeFields,
} from "./saved.ts";
import { newItem } from "./stack.ts";
import { EMPTY_QUERY } from "./targets.ts";
import { closeLabel, draftLine, savedWhen } from "./useComposeDraft.ts";

const fetchCommand = vi.hoisted(() => vi.fn());
vi.mock("../api.ts", async (original) => ({
  ...(await original<typeof import("../api.ts")>()),
  fetchCommand,
}));

const heater: CommandDetail = {
  id: "cmd-1",
  name: "SET_HEATER_SETPOINT",
  display_name: null,
  description: null,
  subsystem: null,
  group: null,
  significance: "routine",
  critical: false,
  hazardous: false,
  second_go_required: false,
  argument_count: 1,
  opcode_json: "18",
  apid: 0,
  release_policy_hint: null,
  arguments: [
    {
      id: "s",
      name: "setpoint",
      description: null,
      type: "float",
      required: true,
      default_value_json: "20.0",
      fixed_value_json: null,
      hazardous_values_json: [],
      choices: [],
      valid_range: { minimum_json: "-40.0", maximum_json: "60.0" },
      unit: "degC",
      current_point: undefined,
    },
  ],
  verifiers: [],
};

const blank: ComposeFields = {
  title: "",
  log: "",
  query: EMPTY_QUERY,
  endpoints: {},
  stack: [],
  release: { mode: "next_contact", notBefore: null, expiresAt: null, priority: 3 },
  approver: "",
  sentBackFrom: null,
};

const stored = (document: unknown, missing: string[] = []) => ({
  revision: 4,
  saved_at: "2026-11-11T02:44:31Z",
  document,
  catalog: { revision_saved: "r1", revision_now: "r1", missing_command_ids: missing },
});

describe("compose draft document", () => {
  const fields: ComposeFields = {
    ...blank,
    title: "Heater trim",
    query: { ...EMPTY_QUERY, plane: 7, explicit: ["sc-1"] },
    endpoints: { "sc-1": "ep-9" },
    stack: [{ ...newItem(heater), values: { s: "abc" } }],
    release: {
      mode: "not_before",
      notBefore: Date.parse("2026-11-12T00:00:00Z"),
      expiresAt: null,
      priority: 3,
    },
    approver: "user-2",
  };

  it("writes schema 1 with raw argument text and an ISO hold time", () => {
    const doc = toDocument(fields);
    expect(doc.schema_version).toBe(1);
    expect(doc.stack[0]).toMatchObject({ command_id: "cmd-1", values: { s: "abc" } });
    expect(doc.release).toEqual({
      mode: "not_before",
      not_before: "2026-11-12T00:00:00.000Z",
      expires_at: null,
      priority: 3,
    });
    expect(doc.requested_approver_user_id).toBe("user-2");
    expect(doc.origin).toBeNull();
    expect(toDocument({ ...fields, sentBackFrom: "g-1" }).origin).toEqual({
      kind: "sent_back",
      id: "g-1",
    });
  });

  it("keeps each target's own values (B2) in the document", () => {
    const [first] = fields.stack;
    if (!first) throw new Error("stack");
    const doc = toDocument({
      ...fields,
      stack: [{ ...first, perTarget: { s: { "spacecraft-earendil-002": "xyz" } } }],
    });
    expect(doc.stack[0]?.per_target).toEqual({ s: { "spacecraft-earendil-002": "xyz" } });
  });

  it("restores fields, keeping invalid text, and counts commands the catalog lost", async () => {
    fetchCommand.mockResolvedValue({
      ok: true,
      value: { revision_id: "rev-3", catalog_revision: null, command: heater },
    });
    const doc = JSON.parse(JSON.stringify(toDocument(fields))) as unknown;
    const r = await restoreDraft(missionIdReader("m"), stored(doc));
    expect(r.ok && r.value.fields.title).toBe("Heater trim");
    expect(r.ok && r.value.fields.stack[0]?.values).toEqual({ s: "abc" });
    expect(r.ok && r.value.fields.release.notBefore).toBe(Date.parse("2026-11-12T00:00:00Z"));
    expect(r.ok && r.value.fields.query.plane).toBe(7);
    // U68: a draft saved before expiry and priority existed restores the defaults.
    const old = {
      ...toDocument(fields),
      release: { mode: "next_contact", not_before: null },
    };
    const back = await restoreDraft(missionIdReader("m"), stored(JSON.parse(JSON.stringify(old))));
    expect(back.ok && back.value.fields.release).toEqual({
      mode: "next_contact",
      notBefore: null,
      expiresAt: null,
      priority: 3,
    });
    const lost = await restoreDraft(missionIdReader("m"), stored(doc, ["cmd-1"]));
    expect(lost.ok && [lost.value.gone, lost.value.fields.stack.length]).toEqual([1, 0]);
  });

  it("refuses a document it can't read rather than guessing", async () => {
    const r = await restoreDraft(missionIdReader("m"), stored({ schema_version: 2 }));
    expect(r.ok).toBe(false);
  });

  it("treats an untouched form as blank", () => {
    expect(isBlank(blank)).toBe(true);
    expect(isBlank({ ...blank, title: "x" })).toBe(false);
  });

  it("reads the 409 details and the header line", () => {
    expect(changedBy({ revision: 5, saved_at: "2026-11-11T02:45:00Z" })?.revision).toBe(5);
    expect(changedBy(undefined)).toBeNull();
    expect(draftLine({ kind: "saved", at: "2026-11-11T02:44:31Z" })).toBe(
      "Draft · saved 02:44:31Z",
    );
    expect(draftLine({ kind: "new" })).toBe("new");
    const now = new Date("2026-11-11T20:00:00Z");
    expect(savedWhen("2026-11-11T02:44:31Z", now)).toBe("02:44Z");
    expect(savedWhen("2026-11-10T02:44:31Z", now)).toBe("11-10 02:44Z");
  });
});

describe("compose draft gone elsewhere", () => {
  it("reads 409 details {revision: null} as gone", () => {
    expect(changedBy({ revision: null, saved_at: null })).toBeNull();
    expect(draftLine({ kind: "conflict", theirs: null })).toBe("Draft · autosave paused");
  });

  it("words a failed save and the close button (ux 601a32f9)", () => {
    const at = new Date().toISOString();
    const hhmm = `${at.slice(11, 16)}Z`;
    expect(draftLine({ kind: "failed", reason: null, lastSaved: null })).toBe("Draft · not saved");
    expect(draftLine({ kind: "failed", reason: null, lastSaved: at })).toBe(
      `Draft · not saved · last saved ${hhmm}`,
    );
    expect(closeLabel("EARENDIL-312", at)).toBe(
      `Close and return to EARENDIL-312 · draft saved ${hhmm}`,
    );
    expect(closeLabel("Commands", null)).toBe("Close and return to Commands");
  });
});

describe("GET /command-draft reply", () => {
  const body = {
    revision: 3,
    saved_at: "2026-11-13T01:00:00Z",
    document: { version: 1 },
    catalog: { revision_saved: null, revision_now: null, missing_command_ids: [] },
  };
  it("reads {draft: null} as no draft (qa a11y #6, api 444a187fc)", () => {
    expect(decode(draftReplyReader, { draft: null })).toEqual({ ok: true, value: { draft: null } });
  });
  it("reads {draft} and refuses a malformed one", () => {
    const r = decode(draftReplyReader, { draft: body });
    expect(r.ok && r.value.draft?.revision).toBe(3);
    expect(decode(draftReplyReader, { draft: { revision: "x" } }).ok).toBe(false);
  });
});
