import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { directoryPageReader } from "./api.ts";

const summary = {
  total: 2,
  profiles: 1,
  without_profile: 1,
  without_scid: 1,
  without_routing_rule: 1,
  awaiting_first_aos: 1,
};

/** A page body: the rows, the whole-mission summary and the telemetry flag every page carries. */
const page = (extra: Record<string, unknown> = {}) => ({
  spacecraft: [],
  summary,
  telemetry: "ok",
  ...extra,
});

const row = (extra: Record<string, unknown> = {}) => ({
  id: "spacecraft-1",
  name: "EARENDIL-312",
  scid: 312,
  norad_id: null,
  plane: 13,
  slot: 12,
  profile: { id: "type_1", name: "Block 1", version: 4 },
  routing_rule_count: 6,
  ready: true,
  last_received_at: "2026-11-08T02:41:15Z",
  ...extra,
});

describe("directoryPageReader", () => {
  it("reads identity columns and keeps null distinct", () => {
    const result = decode(
      directoryPageReader,
      page({
        spacecraft: [
          row(),
          row({
            id: "spacecraft-2",
            scid: null,
            profile: null,
            routing_rule_count: 0,
            ready: false,
            last_received_at: null,
          }),
        ],
      }),
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.rows[1]).toMatchObject({
      scid: null,
      profile: null,
      lastReceivedAt: null,
    });
  });

  it("reads the server's whole-mission summary, not a tally of the rows", () => {
    const result = decode(
      directoryPageReader,
      page({
        spacecraft: [row()],
        summary: {
          total: 1_200,
          profiles: 3,
          without_profile: 4,
          without_scid: 5,
          without_routing_rule: 6,
          awaiting_first_aos: 7,
        },
      }),
    );
    expect(result.ok && result.value.meta.summary).toEqual({
      total: 1_200,
      profiles: 3,
      withoutProfile: 4,
      withoutScid: 5,
      withoutRoute: 6,
      neverHeard: 7,
    });
  });

  it("refuses a page without a summary or with a negative count", () => {
    const { summary: _summary, ...bare } = page();
    expect(decode(directoryPageReader, bare).ok).toBe(false);
    expect(
      decode(directoryPageReader, page({ summary: { ...summary, without_scid: -1 } })).ok,
    ).toBe(false);
  });

  it("holds a page to the server's 500 rows", () => {
    const rows = Array.from({ length: 501 }, (_, i) => row({ id: `spacecraft-${i}` }));
    expect(decode(directoryPageReader, page({ spacecraft: rows })).ok).toBe(false);
  });

  it("rejects a ready row that lacks a routing rule", () => {
    const result = decode(
      directoryPageReader,
      page({ spacecraft: [row({ routing_rule_count: 0 })] }),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.path).toBe("spacecraft[0].ready");
  });

  it("rejects missing columns rather than defaulting them", () => {
    const { plane: _plane, ...withoutPlane } = row();
    expect(decode(directoryPageReader, page({ spacecraft: [withoutPlane] })).ok).toBe(false);
  });
});

describe("S9 (#313): the directory's SCIDs in use", () => {
  it("reads the server's next free SCID and SCIDs in use; null when it doesn't send them", () => {
    const sent = decode(directoryPageReader, page({ next_free_scid: 3, scids_in_use: [1, 2, 7] }));
    expect(sent.ok && sent.value.meta.scids).toEqual({ next: 3, inUse: [1, 2, 7] });
    const full = decode(directoryPageReader, page({ next_free_scid: null, scids_in_use: [] }));
    expect(full.ok && full.value.meta.scids).toEqual({ next: null, inUse: [] });
    const before = decode(directoryPageReader, page());
    expect(before.ok && before.value.meta.scids).toBeNull();
  });

  it("derives the next free SCID from the list when the server leaves it out (mms-engineer)", () => {
    const r = decode(directoryPageReader, page({ scids_in_use: [1, 2, 4] }));
    expect(r.ok && r.value.meta.scids).toEqual({ next: 3, inUse: [1, 2, 4] });
    const taken = Array.from({ length: 1023 }, (_, i) => i + 1);
    const full = decode(directoryPageReader, page({ scids_in_use: taken }));
    expect(full.ok && full.value.meta.scids?.next).toBeNull();
  });

  it("refuses a SCID outside 0..1023", () => {
    expect(decode(directoryPageReader, page({ scids_in_use: [1024] })).ok).toBe(false);
    expect(decode(directoryPageReader, page({ next_free_scid: -1, scids_in_use: [] })).ok).toBe(
      false,
    );
  });
});

/** E2b (#546, #924; U109): a row whose running revision's approval was withdrawn or rejected. */
describe("the directory row's approval_withdrawn", () => {
  const withdrawal = {
    revision_id: "mission_model_revision:r3",
    decision: {
      kind: "withdrawn",
      by: { kind: "user", id: "u-ana", name: "Ana R." },
      at: "2026-11-20T09:12:00Z",
      reason: null,
    },
  };
  it("reads it, and an approved row or a server before #924 as null", () => {
    const sent = decode(
      directoryPageReader,
      page({ spacecraft: [row({ approval_withdrawn: withdrawal })] }),
    );
    expect(sent.ok && sent.value.rows[0]?.approvalWithdrawn?.revision_id).toBe(
      "mission_model_revision:r3",
    );
    const approved = decode(
      directoryPageReader,
      page({ spacecraft: [row({ approval_withdrawn: null })] }),
    );
    expect(approved.ok && approved.value.rows[0]?.approvalWithdrawn).toBeNull();
    const before = decode(directoryPageReader, page({ spacecraft: [row()] }));
    expect(before.ok && before.value.rows[0]?.approvalWithdrawn).toBeNull();
  });
});
