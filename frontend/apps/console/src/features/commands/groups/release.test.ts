import { describe, expect, it } from "vite-plus/test";
import { decode, type ApiError } from "@/api/index.ts";
import { groupOf, showBody } from "./fixtures.ts";
import {
  refusalLine,
  releaseErrorWords,
  releaseLogContext,
  resultLine,
  unbookedSheetBody,
  windowLine,
  type ReleaseResult,
} from "./release.ts";
import { eventText } from "./words.ts";
import { groupUplinkReader } from "@/features/contacts/readiness.ts";

const AT = new Date("2026-11-14T03:15:00Z");
const times = { starts_at: "2026-11-14T03:10:00Z", ends_at: "2026-11-14T03:19:00Z" };
const closed = (why: string) => ({ realized_contact_id: "rc-1", why, ...times });
const conflict = (code: string, details: unknown): ApiError => ({
  kind: "conflict",
  code,
  message: "No.",
  details,
});
const station = { ref: "sva", id: null, code: "SVA", name: "Svalbard A" };
const contact = {
  realized_contact_id: "rc-9",
  booked: false,
  station,
  starts_at: "2026-11-14T00:12:00Z",
  ends_at: null,
  started_by: { kind: "user", id: "user-7", name: "Mira K." },
  started_at: "2026-11-14T00:12:00Z",
  armed_group_ids: ["grp-0", "grp-1", "grp-2"],
};

/** A member's refusal, decoded through the group reader as the server sends it. */
const refusalOf = (code: string, details: unknown, at: string, booked: boolean | null = true) => {
  const g = groupOf({
    targets: [
      {
        ...showBody.targets[0],
        members: [
          {
            ...showBody.targets[0]?.members[0],
            release_refusal: { code, details, at, realized_contact_id: "rc-1", booked },
          },
        ],
      },
    ],
  });
  const r = g.targets[0]?.members[0]?.release_refusal;
  if (!r) throw new Error("no refusal");
  return r;
};

describe("U46 command window and named release words", () => {
  it("reads the command window from the pass times", () => {
    const { starts_at, ends_at } = times;
    expect(windowLine(starts_at, ends_at, new Date("2026-11-14T03:00:00Z"))).toBe(
      "Command window opens at AOS 03:10Z.",
    );
    expect(windowLine(starts_at, ends_at, AT)).toBe("Command window open until LOS 03:19Z.");
    expect(windowLine(starts_at, ends_at, new Date("2026-11-14T03:30:00Z"))).toBe(
      "Command window closed at LOS 03:19Z.",
    );
  });

  it("words a member's window-closed stop: before AOS, after LOS, dropped, unknown", () => {
    expect(
      refusalLine(
        refusalOf("command_window_closed", closed("outside_pass"), "2026-11-14T03:05:00Z"),
      ),
    ).toBe("Not released: the pass hasn't started (AOS 03:10Z).");
    expect(
      refusalLine(
        refusalOf("command_window_closed", closed("outside_pass"), "2026-11-14T03:20:00Z"),
      ),
    ).toBe("Not released: the pass has ended (LOS 03:19Z).");
    expect(
      refusalLine(
        refusalOf("command_window_closed", closed("uplink_leg_dropped"), "2026-11-14T03:12:00Z"),
        { provider: "Northlight" },
      ),
    ).toBe("Not released: Northlight dropped the uplink from this pass.");
    expect(
      refusalLine(refusalOf("command_window_closed", { why: "eclipse" }, "2026-11-14T03:12:00Z")),
    ).toBe("Not released: the command window is closed.");
    expect(refusalLine(refusalOf("command_window_closed", null, "2026-11-14T03:12:00Z"))).toBe(
      "Not released: the command window is closed.",
    );
  });

  it("says contact, not pass, for a hand-started one; unknown codes keep the server's sentence", () => {
    expect(
      refusalLine(
        refusalOf("command_window_closed", closed("outside_pass"), "2026-11-14T03:20:00Z", false),
      ),
    ).toBe("Not released: the contact ended at 03:19Z.");
    expect(
      refusalLine(
        refusalOf("command_window_closed", closed("outside_pass"), "2026-11-14T03:05:00Z", false),
      ),
    ).toBe("Not released: the contact hasn't started.");
    expect(
      refusalLine(
        refusalOf("command_queue_entry_not_next_for_release", null, "2026-11-14T03:12:00Z"),
        { spacecraft: "EARENDIL-001" },
      ),
    ).toBe("Not released: an earlier queued uplink to EARENDIL-001 has to go first.");
    expect(
      refusalLine(
        refusalOf("lane_wedged", { message: "The lane is wedged." }, "2026-11-14T03:12:00Z"),
      ),
    ).toBe("Not released: The lane is wedged.");
    expect(refusalLine(refusalOf("lane_wedged", null, "2026-11-14T03:12:00Z"))).toBe(
      "Not released: lane wedged.",
    );
  });

  it("words each group's outcome", () => {
    const r = (o: Partial<ReleaseResult>): ReleaseResult => ({
      command_group_id: "grp-1",
      outcome: "released",
      released_entry_ids: ["e1", "e2"],
      not_attempted_entry_ids: [],
      stopped: null,
      refused: null,
      ...o,
    });
    const c = { at: AT, booked: false, spacecraft: "EARENDIL-001" };
    expect(resultLine(r({}), c)).toBe("Released 2 uplinks.");
    expect(
      resultLine(
        r({
          outcome: "stopped",
          released_entry_ids: ["e1"],
          not_attempted_entry_ids: ["e3", "e4"],
          stopped: {
            command_queue_entry_id: "e2",
            command_request_id: "req-2",
            code: "earlier_command_failed",
            details: null,
          },
        }),
        c,
      ),
    ).toBe(
      "Released 1 uplink, then stopped: an earlier uplink in it failed. 2 uplinks still queued.",
    );
    expect(
      resultLine(
        r({
          outcome: "refused",
          released_entry_ids: [],
          refused: { code: "command_group_nothing_to_release", details: null },
        }),
        c,
      ),
    ).toBe("Not released: its uplinks to EARENDIL-001 have already gone or ended.");
  });

  it("words whole-request refusals and asks for the sheet on an unconfirmed contact", () => {
    const c = { at: AT, booked: false };
    expect(
      releaseErrorWords(conflict("command_window_closed", closed("uplink_leg_dropped")), c),
    ).toEqual({
      kind: "refused",
      text: "Not released: the provider dropped the uplink from this contact.",
    });
    expect(
      releaseErrorWords(
        conflict("unbooked_contact_unconfirmed", { realized_contact_id: "rc-9" }),
        c,
      ),
    ).toEqual({
      kind: "confirm",
    });
    expect(
      releaseErrorWords(conflict("realized_contact_not_releasable", { state: "completed" }), c),
    ).toEqual({
      kind: "refused",
      text: "Not released: the contact has ended.",
    });
    expect(releaseErrorWords({ kind: "forbidden", code: "forbidden", message: "No." }, c)).toEqual({
      kind: "refused",
      text: "Operators with mission access can release commands.",
    });
  });

  it("reads a hand-started contact with no booked pass, and words the danger sheet", () => {
    const u = decode(groupUplinkReader, {
      spacecraft: { id: "sc-1", name: "EARENDIL-001" },
      pass: null,
      next_pass: null,
      readiness: null,
      contact,
    });
    if (!u.ok) throw u.error;
    const c = u.value.contact;
    expect(c?.armed_group_ids).toEqual(["grp-0", "grp-1", "grp-2"]);
    expect(
      unbookedSheetBody(
        u.value.spacecraft?.name ?? null,
        c?.station.code ?? null,
        c?.started_by?.name ?? null,
        c?.started_at ?? null,
        c?.armed_group_ids.length ?? 0,
        AT,
      ),
    ).toBe(
      "EARENDIL-001's contact at SVA, started by Mira K. at 00:12Z, wasn't booked as a pass. Release 3 requests to it anyway?",
    );
    expect(unbookedSheetBody(null, null, null, null, 1, AT)).toBe(
      "This contact wasn't booked as a pass. Release 1 request to it anyway?",
    );
  });

  it("logs a named release into an unbooked contact", () => {
    const g = groupOf({
      events: [
        {
          id: "ev-9",
          kind: "released_on_contact",
          actor: { actor_kind: "user", user_id: "user-7" },
          at: "2026-11-14T00:14:00Z",
          payload: {
            released_by: { id: "user-7" },
            realized_contact_id: "rc-9",
            booked: false,
            released_entry_ids: ["e1", "e2"],
            not_attempted_entry_ids: ["e3"],
            stopped: {
              command_queue_entry_id: "e3",
              command_request_id: "req-3",
              reason: { code: "earlier_command_failed", details: {} },
            },
          },
        },
      ],
    });
    const e = g.events[0];
    if (!e) throw new Error("no event");
    expect(eventText(e, () => "Mira K.")).toBe(
      "Mira K. released 2 uplinks into a contact that wasn't a booked pass · then stopped: an earlier uplink in it failed · 1 uplink still queued",
    );
  });

  it("logs a named release into a booked pass, by its label when the screen has it", () => {
    const g = groupOf({
      events: [
        {
          id: "ev-10",
          kind: "released_on_contact",
          actor: { actor_kind: "user", user_id: "user-7" },
          at: "2026-11-14T03:14:00Z",
          payload: {
            realized_contact_id: "rc-1",
            booked: true,
            released_entry_ids: ["e1", "e2"],
            not_attempted_entry_ids: [],
            stopped: null,
          },
        },
      ],
    });
    const e = g.events[0];
    if (!e) throw new Error("no event");
    const u = decode(groupUplinkReader, {
      spacecraft: { id: "sc-1", name: "EARENDIL-001" },
      pass: {
        reservation_id: "pass-1",
        contact_id: "c-1",
        station,
        starts_at: "2026-11-14T03:10:00Z",
        ends_at: "2026-11-14T03:19:00Z",
        booked: true,
        realized_contact_id: "rc-1",
      },
      readiness: null,
      contact: null,
    });
    if (!u.ok) throw u.error;
    expect(eventText(e, () => "Mira K.", [], releaseLogContext(u.value, null))).toBe(
      "Mira K. released 2 uplinks into the SVA 03:10Z pass",
    );
    expect(eventText(e, () => "Mira K.")).toBe("Mira K. released 2 uplinks into a booked pass");
  });

  it("names the spacecraft only when it's known to be the contact's (U25), and dates the label", () => {
    const stoppedAt = (rc: string, at: string) =>
      groupOf({
        events: [
          {
            id: "ev-11",
            kind: "released_on_contact",
            actor: { actor_kind: "user", user_id: "user-7" },
            at,
            payload: {
              realized_contact_id: rc,
              booked: true,
              released_entry_ids: [],
              not_attempted_entry_ids: ["e2"],
              stopped: {
                command_queue_entry_id: "e1",
                command_request_id: "req-1",
                reason: { code: "command_queue_entry_not_next_for_release", details: {} },
              },
            },
          },
        ],
      }).events[0];
    const u = decode(groupUplinkReader, {
      spacecraft: { id: "sc-1", name: "EARENDIL-001" },
      pass: {
        reservation_id: "pass-1",
        contact_id: "c-1",
        station,
        starts_at: "2026-11-14T03:10:00Z",
        ends_at: "2026-11-14T03:19:00Z",
        realized_contact_id: "rc-1",
      },
      readiness: null,
    });
    if (!u.ok) throw u.error;
    const several = releaseLogContext(u.value, null);
    const ours = stoppedAt("rc-1", "2026-11-15T00:10:00Z");
    const other = stoppedAt("rc-7", "2026-11-14T03:14:00Z");
    if (!ours || !other) throw new Error("no event");
    expect(eventText(ours, () => "Mira K.", [], several)).toBe(
      "Mira K. released 0 uplinks into the SVA 11-14 03:10Z pass · then stopped: an earlier queued uplink to EARENDIL-001 has to go first · 1 uplink still queued",
    );
    expect(eventText(other, () => "Mira K.", [], several)).toBe(
      "Mira K. released 0 uplinks into a booked pass · then stopped: an earlier queued uplink to the contact's spacecraft has to go first · 1 uplink still queued",
    );
    expect(eventText(other, () => "Mira K.", [], releaseLogContext(u.value, "SC-1"))).toContain(
      "an earlier queued uplink to SC-1 has to go first",
    );
  });
});
