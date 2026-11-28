import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import {
  missionId as missionIdReader,
  spacecraftId as spacecraftIdReader,
  decode,
  pointId as pointIdReader,
} from "@/api/index.ts";
import {
  episodeEventReader,
  episodeFor,
  episodesReader,
  runEpisodeCommand,
  type EpisodeDetail,
} from "./episodes.ts";
import { episodeFixture } from "./fixtures.ts";
import {
  escalationNotice,
  eventState,
  eventText,
  sourceTag,
  statusLine,
  lastValueReadout,
} from "./episodeText.ts";

const episode = episodeFixture;
const now = new Date("2026-11-08T02:44:00Z");

describe("alarm episodes", () => {
  it("decodes the list and finds the episode behind an alarm row", () => {
    const body = {
      summary: { active: 1 },
      permissions: ["alarm.acknowledge"],
      episodes: [episode()],
    };
    const result = decode(episodesReader, body);
    expect(result.ok).toBe(true);
    expect(
      episodeFor(
        [episode(), episode({ id: "x", status: "cleared" })],
        spacecraftIdReader("sc-312"),
        pointIdReader("EPS.VBAT"),
      )?.id,
    ).toBe("alarm_episode_1");
    expect(
      episodeFor(
        [episode({ status: "cleared" })],
        spacecraftIdReader("sc-312"),
        pointIdReader("EPS.VBAT"),
      ),
    ).toBeNull();
  });

  it("never implies ground limits are live (U16)", () => {
    expect(sourceTag(episode(), now)).toBe("Ground limits · evaluated 02:41:00Z · T+00:03:00");
    expect(sourceTag(episode({ source: "catalog_monitoring" }), now)).toBe("Live");
  });

  it("reads the value as the episode's last, with its time, never as live (#1117)", () => {
    expect(lastValueReadout(episode(), now)).toEqual({
      label: "Last value",
      value: "23.1",
      caption: "at 02:41:00Z",
    });
    expect(lastValueReadout(episode(), new Date("2026-11-09T09:00:00Z"))?.caption).toBe(
      "at 2026-11-08 02:41:00Z",
    );
    expect(lastValueReadout(episode({ last_evaluated_at: null }), now)?.caption).toBe(
      "time not reported",
    );
    // No episode, or no value: no readout at all (an always-empty tile is noise).
    expect(lastValueReadout(null, now)).toBeNull();
    expect(lastValueReadout(episode({ last_value: null }), now)).toBeNull();
  });

  it("states status, ack and assignee in words", () => {
    expect(statusLine(episode()).text).toBe("New");
    const acked = episode({
      status: "acknowledged",
      acknowledged_by: { kind: "user", id: "u1", name: "Mira K." },
      assignee: { kind: "user" as const, id: "u2", name: "Ana P." },
    });
    expect(statusLine(acked).text).toBe("Acknowledged by Mira K. · assigned to Ana P.");
    const mine = episode({
      status: "acknowledged",
      acknowledged_at: "2026-11-09T01:09:30Z",
      acknowledged_by: { kind: "user", id: "me", name: "Donovan R." },
    });
    expect(statusLine(mine, "me").text).toBe("Acknowledged by you · 01:09Z");
    expect(statusLine(episode({ status: "cleared", cleared_unacknowledged: true })).text).toBe(
      "Cleared before anyone acknowledged",
    );
  });

  it("explains an escalation that cleared the acknowledgement", () => {
    const detail: EpisodeDetail = {
      ...episode(),
      events: [
        {
          id: "e1",
          kind: "raised",
          actor: null,
          at: "2026-11-08T02:35:02Z",
          sample: undefined,
          payload: {},
        },
        {
          id: "e2",
          kind: "escalated",
          sample: undefined,
          actor: null,
          at: "2026-11-08T02:40:00Z",
          payload: { from: "caution", to: "critical", acknowledgement_cleared: true },
        },
      ],
    };
    expect(escalationNotice(detail)).toBe("Ack cleared · escalated to critical");
    const escalated = detail.events[1];
    expect(escalated && eventText(escalated)).toBe(
      "Escalated to critical · acknowledgement cleared",
    );
    expect(escalationNotice({ ...detail, status: "acknowledged" })).toBeNull();
    // ux #14: no flag in the payload; inferred from an ack before the escalation and none after.
    const inferred: EpisodeDetail = {
      ...episode(),
      events: [
        {
          id: "a",
          kind: "acknowledged",
          actor: null,
          at: "2026-11-08T02:36:00Z",
          sample: undefined,
          payload: {},
        },
        {
          id: "b",
          kind: "escalated",
          sample: undefined,
          actor: null,
          at: "2026-11-08T02:40:00Z",
          payload: { from: "caution", to: "critical" },
        },
      ],
    };
    expect(escalationNotice(inferred)).toBe("Ack cleared · escalated to critical");
    const neverAcked: EpisodeDetail = { ...inferred, events: inferred.events.slice(1) };
    expect(escalationNotice(neverAcked)).toBeNull();
  });
});

describe("episode commands (U20 outcomes)", () => {
  afterEach(() => vi.unstubAllGlobals());
  const respond = (status: number, body: unknown) =>
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response(JSON.stringify(body), { status })),
    );

  it("calls a 409 rejected (nothing changed) and a 503 unclear", async () => {
    respond(409, { error: { code: "episode_cleared", message: "Already cleared." } });
    expect(
      (await runEpisodeCommand(missionIdReader("m"), "e", { kind: "acknowledge" })).status,
    ).toBe("rejected");
    respond(503, { error: { code: "alarms_unavailable", message: "Down." } });
    expect(
      (await runEpisodeCommand(missionIdReader("m"), "e", { kind: "acknowledge" })).status,
    ).toBe("unclear");
  });

  it("treats an unreadable success as unclear, not done", async () => {
    respond(200, { data: { nope: true } });
    expect(
      (await runEpisodeCommand(missionIdReader("m"), "e", { kind: "acknowledge" })).status,
    ).toBe("unclear");
  });
});

describe("episode event kinds (#1072, rule 3)", () => {
  /** Synthetic events in alarms-console.md's shape (#451, #1072), not captured from a server. */
  const event = (kind: string, payload: unknown = {}) => {
    const r = decode(episodeEventReader, {
      id: `ev-${kind}`,
      kind,
      actor: null,
      at: "2026-11-27T10:02:00Z",
      payload,
    });
    if (!r.ok) throw new Error(JSON.stringify(r.error));
    return r.value;
  };

  it("words rule_changed: the alarm's limits changed, the episode itself didn't", () => {
    const e = event("rule_changed", { from: "d1", to: "d2", rule_ids: ["r1"], policy_id: "p1" });
    expect([eventText(e), eventState(e)]).toEqual(["The limits for this alarm changed", "neutral"]);
  });

  it("reads a kind this console doesn't know as a neutral line with the server's word", () => {
    const e = event("rule_reset");
    expect(e.kind).toEqual({ unrecognized: "rule_reset" });
    expect([eventText(e), eventState(e)]).toEqual(["Rule reset", "neutral"]);
  });
});
