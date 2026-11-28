import { describe, expect, it } from "vite-plus/test";
import { spacecraftId as spacecraftIdReader, pointId as pointIdReader } from "@/api/index.ts";
import type { Alarm } from "@/features/alarms/index.ts";
import type { GroupRow } from "@/features/commands/index.ts";
import { spacecraftRow } from "@/features/fleet/index.ts";
import { ago, alarmItems, MOBILE_GROUPS, phoneSpacecraftItems, requestItems } from "./mobile.ts";
import { grouped } from "./results.ts";

const now = Date.parse("2026-11-13T03:00:00Z");
const fleet = [spacecraftRow(312, { state: "critical" }), spacecraftRow(31)];
const byId = new Map(fleet.map((sc) => [sc.id, sc]));

const alarm = (id: string, sc: string, point: string, extra: Partial<Alarm> = {}): Alarm => ({
  id,
  spacecraft_id: spacecraftIdReader(sc),
  point: {
    id: pointIdReader(`pt-${point}`),
    name: point,
    subsystem: null,
    unit: "V",
    description: null,
  },
  severity: "critical",
  active: true,
  condition: "red_low",
  value: 23.1,
  limit_set_name: null,
  thresholds: { red_low: 24, yellow_low: 25, yellow_high: null, red_high: null },
  first_crossed_at: "2026-11-13T02:57:00Z",
  generation_time: null,
  received_at: null,
  ...extra,
});

const request = (id: string, title: string, extra: Partial<GroupRow> = {}): GroupRow => ({
  id,
  state: "approval_pending",
  title,
  requested_by: { actor_kind: "user", user_id: "u-mira" },
  requested_at: "2026-11-13T02:48:00Z",
  requested_approver_user_id: null,
  member_count: 4,
  target_count: 4,
  command_count: 1,
  second_go_required: false,
  awaiting_me: false,
  operation_id: null,
  priority: undefined,
  expiry: undefined,
  progress: null,
  finished: null,
  uplink: null,
  ...extra,
});

describe("phone search (Mobile.md › Search)", () => {
  it("finds an alarm by spacecraft or point, in words, with the red limit and age", () => {
    const [item] = alarmItems([alarm("a1", fleet[0]?.id ?? "", "VBAT")], byId, "312", now);
    expect(item).toMatchObject({
      group: "Alarms",
      title: "EARENDIL-312 · VBAT below red limit",
      subtitle: "23.1 V · red 24.0 V · T+3m",
      state: "crit",
      to: {
        name: "ops.spacecraft",
        params: { scId: 312, tab: "investigate" },
        query: { point: "pt-VBAT" },
      },
    });
    expect(alarmItems([alarm("a1", fleet[0]?.id ?? "", "VBAT")], byId, "vbat", now)).toHaveLength(
      1,
    );
    expect(
      alarmItems([alarm("a1", fleet[0]?.id ?? "", "VBAT", { active: false })], byId, "vbat", now),
    ).toEqual([]);
  });

  it("puts requests awaiting your GO first and opens them on Approve; others open read-only", () => {
    const items = requestItems(
      [
        request("g1", "Low power safe"),
        request("g2", "Low power safe", { awaiting_me: true }),
        request("g3", "Low power done", { state: "queued", finished: true }),
      ],
      "low",
      () => "Mira K.",
      now,
    );
    expect(items.map((i) => [i.title, i.subtitle])).toEqual([
      ["Low power safe · 4 SC", "Your GO · Mira K. · T+12m"],
      ["Low power safe · 4 SC", "Waiting for approval · Mira K. · T+12m"],
    ]);
    expect(items[0]?.to).toEqual({
      name: "ops.commands.request",
      params: { requestId: "g2", view: "review" },
    });
    expect(items[1]?.to).toMatchObject({ params: { view: "uplink" } });
  });

  it("matches spacecraft by number, opens Investigate, and orders the groups Alarms → Requests → Spacecraft", () => {
    const sc = phoneSpacecraftItems(fleet, "312");
    expect(sc[0]).toMatchObject({
      title: "EARENDIL-312",
      subtitle: "SCID 312 · P13 · critical",
      to: { name: "ops.spacecraft", params: { scId: 312, tab: "investigate" } },
      commandTo: null,
    });
    const items = [
      ...sc,
      ...requestItems([request("g1", "312 reset")], "312", () => "Mira K.", now),
      ...alarmItems([alarm("a1", fleet[0]?.id ?? "", "VBAT")], byId, "312", now),
    ];
    expect(grouped(items, new Set(), MOBILE_GROUPS).map((g) => g.group)).toEqual([
      "Alarms",
      "Requests",
      "Spacecraft",
    ]);
    expect(phoneSpacecraftItems(fleet, "")).toEqual([]);
  });

  it("says age in the largest whole unit", () => {
    expect(ago("2026-11-13T02:59:50Z", now)).toBe("T+1m");
    expect(ago("2026-11-13T00:30:00Z", now)).toBe("T+2h");
    expect(ago("2026-11-10T03:00:00Z", now)).toBe("T+3d");
    expect(ago(null, now)).toBeNull();
  });
});
