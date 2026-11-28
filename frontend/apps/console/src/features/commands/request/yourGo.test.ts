import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId as missionIdReader, decode } from "@/api/index.ts";
import { preflightReader, type Preflight } from "../groups/api.ts";
import { groupOf, showBody } from "../groups/fixtures.ts";
import { namelessTargets, phoneGoBlocked, requestFor, yourGoWords } from "./yourGo.ts";

const review = (checks: unknown[]): Preflight => {
  const r = decode(preflightReader, {
    valid: true,
    digest: "d",
    members: 1,
    second_go_required: true,
    targets: [],
    checks,
  });
  if (!r.ok) throw r.error;
  return r.value;
};
const names = (id: string | null) => (id === "user-1" ? "Mira K." : "Someone");
const reply = (body: unknown) =>
  new Response(JSON.stringify({ data: body }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
const row = (id: string, at: string) => {
  const { events: _e, targets: _t, commands: _c, ...rest } = showBody;
  return { ...rest, id, requested_at: at, progress: null, finished: null, uplink: null };
};

describe("Mobile 'Your GO is requested' (Mobile.md §3)", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("finds the oldest request awaiting your GO that targets this spacecraft", async () => {
    // #795: each request is asked for a targets page searched by the id, never read whole; q is
    // a substring match, so grp-old's SC-10 doesn't count for sc-1.
    const page = (ids: string[]) =>
      new Response(
        JSON.stringify({
          data: {
            targets: ids.map((id, i) => ({ ...showBody.targets[0], index: i, spacecraft_id: id })),
          },
          meta: { total: ids.length, next_cursor: null },
        }),
        { status: 200 },
      );
    const asked: string[] = [];
    const fetch = vi.fn((url: string) => {
      asked.push(url);
      if (url.includes("/targets?"))
        return Promise.resolve(page(url.includes("grp-old") ? ["sc-10"] : ["sc-1"]));
      if (url.endsWith("/grp-new")) return Promise.resolve(reply({ ...showBody, id: "grp-new" }));
      return Promise.resolve(
        reply({
          groups: [row("grp-new", "2026-11-12T03:00:00Z"), row("grp-old", "2026-11-12T01:00:00Z")],
        }),
      );
    });
    vi.stubGlobal("fetch", fetch);
    const r = await requestFor(missionIdReader("m"), "sc-1");
    expect(r.ok && r.value?.id).toBe("grp-new");
    expect(asked.filter((u) => u.includes("/targets?"))).toHaveLength(2);
    expect(asked.some((u) => u.endsWith("/grp-old"))).toBe(false);
  });

  it("words the block and says when GO has to go through the full review", () => {
    const g = groupOf({ target_count: 4, member_count: 4 });
    const w = yourGoWords(g, names, new Date("2026-11-08T02:12:00Z"));
    expect([w.title, w.by, w.release, w.stack, w.confirm]).toEqual([
      "Reset watchdogs · 4 spacecraft",
      "Mira K. · T+00:12:00",
      "Each target at its next AOS.",
      ["01 FORCE_WATCHDOG"],
      "Sign GO for 4 targets and 4 uplinks?",
    ]);
    // ux on #580: a large count takes its thousands separator.
    expect(
      yourGoWords(groupOf({ target_count: 1200, member_count: 1200 }), names, new Date()).title,
    ).toBe("Reset watchdogs · 1,200 spacecraft");
    expect(phoneGoBlocked(g, null, [], "user-1", true, names)).toMatch(/your own request/);
    expect(phoneGoBlocked(g, null, [], "user-9", true, names)).toBe("Re-checking before GO…");
    // #795: the HOLD acks are their own read; GO waits for it as it waits for the re-check.
    expect(phoneGoBlocked(g, review([]), null, "user-9", true, names)).toBe(
      "Re-checking before GO…",
    );
    const noGo = review([{ key: "catalog", result: "no_go", per_target: [], evidence: {} }]);
    expect(phoneGoBlocked(g, noGo, [], "user-9", true, names)).toBe(
      "The Catalog re-check is NO-GO.",
    );
    expect(phoneGoBlocked(g, review([]), [], "user-9", true, names)).toBeNull();
  });

  it("cautions about targets with no name without blocking GO, ids kept for Technical details (#237)", () => {
    const g = groupOf({});
    expect(namelessTargets(g)).toBeNull();
    const target = showBody.targets[0];
    if (!target) throw new Error("fixture");
    const one = groupOf({ targets: [{ ...target, name: null }] });
    expect(namelessTargets(one)).toEqual({
      line: "This console can't show the name of 1 target spacecraft. Check its id in Technical details before you give GO.",
      ids: [target.spacecraft_id],
    });
    const two = groupOf({
      targets: [
        { ...target, name: null },
        { ...target, spacecraft_id: "sc-9", name: null },
      ],
    });
    expect(namelessTargets(two)?.line).toMatch(/of 2 target spacecraft\. Check their ids/);
    expect(phoneGoBlocked(one, review([]), [], "user-9", true, names)).toBeNull();
    // #795: past the first page it says the count covers the targets read, not the request.
    const paged = groupOf({
      targets: [{ ...target, name: null }],
      target_count: 1_500,
      targets_page: { total: 1_500, revision: 1, next_cursor: "c1" },
    });
    expect(namelessTargets(paged)?.line).toMatch(/1 target spacecraft among the first 1\./);
  });
});
