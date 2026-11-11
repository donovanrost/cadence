import { effectScope, nextTick, ref } from "vue";
import { useHeldNewest } from "./useHeldNewest.ts";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import { eventsReader, type MissionEvent } from "./api.ts";
import {
  byHour,
  densityBars,
  densityBucketS,
  kindLabel,
  needsSpacecraftPrefix,
  severityState,
  subjectLink,
  scopeOptions,
  scopeQuery,
  scopeValue,
  timelineScope,
  withAlertingData,
} from "./model.ts";

const ev = (id: string, at: string, severity: MissionEvent["severity"] = "info"): MissionEvent => ({
  id,
  at,
  kind: "limit",
  severity,
  raw_kind: "limit_violation",
  text: "VBAT crossed red low",
  detail: null,
  spacecraft: null,
  refs: {
    alarm_id: null,
    point_id: null,
    command_request_id: null,
    contact_id: null,
    subject: null,
  },
});

describe("timeline", () => {
  it("decodes the proposed events shape and rejects unknown kinds", () => {
    const body = {
      from: "2026-11-08T00:00:00Z",
      to: "2026-11-08T01:00:00Z",
      events: [ev("a", "2026-11-08T00:10:00Z")],
    };
    expect(decode(eventsReader, body).ok).toBe(true);
    expect(
      decode(eventsReader, { ...body, events: [{ ...ev("a", "2026-11-08T00:10:00Z"), kind: "x" }] })
        .ok,
    ).toBe(false);
  });

  it("groups newest first under UTC hours", () => {
    const groups = byHour([
      ev("a", "2026-11-08T01:05:00Z"),
      ev("b", "2026-11-08T02:30:00Z"),
      { ...ev("c", "2026-11-08T02:10:00Z"), text: "AOS Svalbard" },
    ]);
    expect(groups.map((g) => [g.hour, g.rows.map((r) => r.event.id)])).toEqual([
      ["2026-11-08 02:00Z", ["b", "c"]],
      ["2026-11-08 01:00Z", ["a"]],
    ]);
  });

  it("collapses consecutive identical events into one row with a count", () => {
    const [group] = byHour([
      ev("a", "2026-11-08T02:30:03Z"),
      ev("b", "2026-11-08T02:30:02Z"),
      ev("c", "2026-11-08T02:30:01Z"),
      { ...ev("d", "2026-11-08T02:29:00Z"), text: "Something else" },
    ]);
    expect(group?.rows.map((r) => [r.event.id, r.count, r.firstAt])).toEqual([
      ["a", 3, "2026-11-08T02:30:01Z"],
      ["d", 1, "2026-11-08T02:29:00Z"],
    ]);
  });

  it("folds the same event across more than three spacecraft in one minute (ux 6)", () => {
    const sc = (n: number) => ({ id: `sc-${n}`, name: `EARENDIL-${n}`, scid: n });
    const realized = (n: number) => ({
      ...ev(`r${n}`, "2026-11-08T02:30:05Z"),
      kind: "contact" as const,
      text: "Realized contact interval",
      spacecraft: sc(n),
    });
    const [group] = byHour([1, 2, 3, 4, 5].map(realized));
    expect(group?.rows).toHaveLength(1);
    expect(group?.rows[0]?.members).toHaveLength(5);
    const [few] = byHour([1, 2, 3].map(realized));
    expect(few?.rows).toHaveLength(3);
  });

  it("sizes density buckets and stacks severities", () => {
    expect(densityBucketS(24 * 3_600_000)).toBe(900);
    expect(densityBucketS(3_600_000)).toBe(60);
    const { bars, max } = densityBars({
      bucket_s: 900,
      truncated: false,
      buckets: [{ t: "2026-11-08T00:00:00Z", critical: 1, caution: 0, nominal: 0, info: 3 }],
    });
    expect(max).toBe(4);
    expect(bars[0]?.stack.map((s) => [s.severity, s.from, s.to])).toEqual([
      ["critical", 0, 0.25],
      ["info", 0.25, 1],
    ]);
  });

  it("maps severities to marks", () => {
    expect(severityState("info")).toBe("neutral");
    expect(severityState("critical")).toBe("crit");
  });
});

describe("event subjects (ux timeline #1)", () => {
  it("links the subject, and skips the spacecraft prefix the sentence already names", () => {
    const sc = { id: "sc-4", name: "EARENDIL-004", scid: 4 };
    const contact = {
      ...ev("c", "2026-11-09T10:23:52Z"),
      kind: "contact" as const,
      text: "Contact with EARENDIL-004 completed, 10:22:54Z–10:23:52Z",
      spacecraft: sc,
      refs: { ...ev("c", "x").refs, subject: { kind: "contact", id: "ct-1", name: null } },
    };
    expect(subjectLink(contact)).toEqual({ name: "ops.contacts", query: { contact: "ct-1" } });
    expect(needsSpacecraftPrefix(contact)).toBe(false);
    expect(needsSpacecraftPrefix({ ...contact, text: "Limit violation" })).toBe(true);
    const activation = {
      ...contact,
      refs: { ...contact.refs, subject: { kind: "activation", id: "a", name: null } },
    };
    expect(subjectLink(activation)).toBeNull();
  });
});

describe("fan-out on kind + minute (ux timeline 7/8)", () => {
  it("folds per-spacecraft sentences and spacecraft-less events, with the worst mark", () => {
    const completed = (n: number) => ({
      ...ev(`r${n}`, "2026-11-09T10:22:54Z"),
      kind: "operator" as const,
      raw_kind: "realized_contact_interval",
      text: `Contact with EARENDIL-00${n} completed`,
      spacecraft: { id: `sc-${n}`, name: `EARENDIL-00${n}`, scid: n },
    });
    const [g] = byHour([1, 2, 3, 4].map(completed));
    expect(g?.rows).toHaveLength(1);
    expect(g?.rows[0]?.label).toBe("Contacts ended (not verified)");

    const canceled = (n: number, severity: MissionEvent["severity"]) => ({
      ...ev(`c${n}`, `2026-11-09T10:47:0${n}Z`, severity),
      raw_kind: "scheduled_contact_canceled",
      text: "Contact for a spacecraft canceled by the provider",
    });
    const [c] = byHour([
      canceled(1, "info"),
      canceled(2, "caution"),
      canceled(3, "info"),
      canceled(4, "caution"),
    ]);
    expect(c?.rows).toHaveLength(1);
    expect(c?.rows[0]?.members).toHaveLength(4);
    expect(c?.rows[0]?.event.severity).toBe("caution");
    expect(c?.rows[0]?.label).toBe("Contacts canceled by the provider");
    expect(kindLabel({ ...canceled(1, "info"), raw_kind: "station_went_dark" })).toBe(
      "Station went dark",
    );
  });
});

describe("timeline scope (backlog §2)", () => {
  const fleet = [
    { id: "sc-4", scid: 4, name: "EARENDIL-004", plane: 1 },
    { id: "sc-21", scid: 21, name: "EARENDIL-021", plane: 2 },
  ];
  it("reads ?sc= through the fleet, ?plane=, else the fleet", () => {
    expect(timelineScope({ sc: "4" }, fleet)).toEqual({
      kind: "spacecraft",
      id: "sc-4",
      scid: 4,
      name: "EARENDIL-004",
    });
    expect(timelineScope({ sc: "999" }, fleet)).toEqual({ kind: "fleet" });
    expect(timelineScope({ plane: "2" }, fleet)).toEqual({ kind: "plane", plane: 2 });
    expect(timelineScope({ plane: "x" }, fleet)).toEqual({ kind: "fleet" });
    expect(timelineScope({}, fleet)).toEqual({ kind: "fleet" });
  });
  it("offers the fleet, the chosen spacecraft and each plane; maps choices to the URL", () => {
    const s = timelineScope({ sc: "4" }, fleet);
    expect(scopeOptions(fleet, s).map((o) => o.label)).toEqual([
      "Whole fleet",
      "EARENDIL-004",
      "Plane 1",
      "Plane 2",
    ]);
    expect(scopeValue(s)).toBe("sc:4");
    expect(scopeQuery("plane:2")).toEqual({ plane: "2", sc: undefined });
    expect(scopeQuery("fleet")).toEqual({ sc: undefined, plane: undefined });
  });
});

describe("live prepend hold (lead 79ec6dc6)", () => {
  it("shows new events at the top, holds them when scrolled away", async () => {
    const scope = effectScope();
    const incoming = ref<readonly { id: string }[] | null>([{ id: "a" }]);
    const el = document.createElement("div");
    const held = scope.run(() => useHeldNewest(incoming, ref(el)));
    if (!held) throw new Error("no scope");
    incoming.value = [{ id: "b" }, { id: "a" }];
    await nextTick();
    expect(held.shown.value?.map((e) => e.id)).toEqual(["b", "a"]);
    el.scrollTop = 400;
    el.dispatchEvent(new Event("scroll"));
    incoming.value = [{ id: "d" }, { id: "c" }, { id: "b" }, { id: "a" }];
    await nextTick();
    expect(held.shown.value?.map((e) => e.id)).toEqual(["b", "a"]);
    expect(held.pending.value).toBe(2);
    el.scrollTop = 0;
    el.dispatchEvent(new Event("scroll"));
    expect(held.shown.value?.map((e) => e.id)).toEqual(["d", "c", "b", "a"]);
    scope.stop();
  });
});

describe("default view shows failing data events (ux)", () => {
  it("merges caution/critical data events, newest first, and drops routine ones", () => {
    const e = (id: string, at: string, severity: string) => ({ id, at, severity });
    const merged = withAlertingData(
      [e("a", "2026-11-10T01:00:00Z", "info")],
      [
        e("d1", "2026-11-10T02:00:00Z", "caution"),
        e("d2", "2026-11-10T03:00:00Z", "info"),
        e("a", "2026-11-10T01:00:00Z", "critical"),
      ],
    );
    expect(merged.map((x) => x.id)).toEqual(["d1", "a"]);
  });
});
