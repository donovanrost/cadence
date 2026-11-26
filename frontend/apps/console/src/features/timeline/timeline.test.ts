import { effectScope, nextTick, ref } from "vue";
import { useHeldNewest } from "./useHeldNewest.ts";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import type { MissionId } from "@/api/index.ts";
import { scid as scidReader, spacecraftId, decode } from "@/api/index.ts";
import { eventsReader, fetchEventPage, type MissionEvent } from "./api.ts";
import {
  byHour,
  densityBars,
  densityBucketS,
  kindLabel,
  needsSpacecraftPrefix,
  severityState,
  brushRange,
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
  record: null,
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
    const sc = (n: number) => ({
      id: spacecraftId(`sc-${n}`),
      name: `EARENDIL-${n}`,
      scid: scidReader(n),
    });
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
    const sc = { id: spacecraftId("sc-4"), name: "EARENDIL-004", scid: scidReader(4) };
    const contact = {
      ...ev("c", "2026-11-09T10:23:52Z"),
      kind: "contact" as const,
      text: "Contact with EARENDIL-004 completed, 10:22:54Z–10:23:52Z",
      spacecraft: sc,
      refs: { ...ev("c", "x").refs, subject: { kind: "contact" as const, id: "ct-1", name: null } },
    };
    expect(subjectLink(contact)).toEqual({ name: "ops.contacts", query: { contact: "ct-1" } });
    expect(needsSpacecraftPrefix(contact)).toBe(false);
    expect(needsSpacecraftPrefix({ ...contact, text: "Limit violation" })).toBe(true);
    const activation = {
      ...contact,
      refs: { ...contact.refs, subject: { kind: "activation" as const, id: "a", name: null } },
    };
    expect(subjectLink(activation)).toBeNull();
    // api 8d: 'Applied r6 · 2 changes' links to Setup's revisions.
    const applied = {
      ...contact,
      kind: "config" as const,
      spacecraft: null,
      refs: { ...contact.refs, subject: { kind: "config_revision" as const, id: "6", name: "r6" } },
    };
    expect(subjectLink(applied)).toEqual({ name: "setup.revisions" });
    // L15 (api dc68a1cb4): an off-plan booking opens its pass in Contacts.
    const booked = {
      ...contact,
      refs: { ...contact.refs, subject: { kind: "pass" as const, id: "res-9", name: null } },
    };
    expect(subjectLink(booked)).toEqual({ name: "ops.contacts", query: { contact: "res-9" } });
  });
});

describe("fan-out on kind + minute (ux timeline 7/8)", () => {
  it("folds per-spacecraft sentences and spacecraft-less events, with the worst mark", () => {
    const completed = (n: number) => ({
      ...ev(`r${n}`, "2026-11-09T10:22:54Z"),
      kind: "operator" as const,
      raw_kind: "realized_contact_interval",
      text: `Contact with EARENDIL-00${n} completed`,
      spacecraft: { id: spacecraftId(`sc-${n}`), name: `EARENDIL-00${n}`, scid: scidReader(n) },
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
    expect(c?.rows[0]?.label).toBe("Contacts canceled");
    expect(kindLabel({ ...canceled(1, "info"), raw_kind: "station_went_dark" })).toBe(
      "Station went dark",
    );
    // U60: the watermark state changes fold in operator words; old advanced rows keep theirs.
    const fold = (raw_kind: string) => kindLabel({ ...canceled(1, "info"), raw_kind });
    expect(fold("source_watermark_settled")).toBe("Telemetry stored");
    expect(fold("source_watermark_caught_up")).toBe("Telemetry caught up");
    expect(fold("source_watermark_retreated")).toBe("Telemetry moved back");
    expect(fold("source_watermark_advanced")).toBe("Data sources caught up");
  });
});

describe("timeline scope (backlog §2)", () => {
  const fleet = [
    { id: "sc-4", scid: scidReader(4), name: "EARENDIL-004", plane: 1 },
    { id: "sc-21", scid: scidReader(21), name: "EARENDIL-021", plane: 2 },
  ];
  it("reads ?sc= through the fleet, ?plane=, else the fleet", () => {
    expect(timelineScope({ sc: "4" }, fleet)).toEqual({
      kind: "spacecraft",
      id: "sc-4",
      scid: scidReader(4),
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

describe("E1 brush (OpsLists §Timeline)", () => {
  it("turns a drag into a window; a click isn't one", () => {
    const w = { from: 0, to: 1000 };
    expect(brushRange(w, 0.6, 0.2)).toEqual({ from: 200, to: 600 });
    expect(brushRange(w, 0.5, 0.505)).toBeNull();
  });
});

describe("a full events read is never cut silently (parity D2, now A9d pages)", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("asks for an older page by cursor and splits it into events, next cursor and window", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>();
    fetch.mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          data: {
            from: "2026-11-15T00:00:00Z",
            to: "2026-11-16T00:00:00Z",
            events: [ev("b", "2026-11-15T10:00:00Z")],
          },
          meta: { next_cursor: "c2" },
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );
    vi.stubGlobal("fetch", fetch);
    const query = { from: new Date("2026-11-15T00:00:00Z"), to: new Date("2026-11-16T00:00:00Z") };
    const r = await fetchEventPage("m1" as MissionId, query, "c1");
    const input = fetch.mock.calls[0]?.[0];
    const url = input instanceof Request ? input.url : (input?.toString() ?? "");
    expect(url).toContain("cursor=c1");
    expect(url).toContain("limit=500");
    expect(r.ok && r.value.items.map((e) => e.id)).toEqual(["b"]);
    expect(r.ok && r.value.next).toBe("c2");
    expect(r.ok && r.value.meta).toEqual({
      from: "2026-11-15T00:00:00Z",
      to: "2026-11-16T00:00:00Z",
    });
  });
});
