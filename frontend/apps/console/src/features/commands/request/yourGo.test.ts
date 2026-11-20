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
    const fetch = vi.fn();
    fetch.mockResolvedValueOnce(
      reply({
        groups: [row("grp-new", "2026-11-12T03:00:00Z"), row("grp-old", "2026-11-12T01:00:00Z")],
      }),
    );
    fetch.mockResolvedValueOnce(
      reply({
        ...showBody,
        id: "grp-old",
        targets: [{ ...showBody.targets[0], spacecraft_id: "sc-9" }],
      }),
    );
    fetch.mockResolvedValueOnce(reply({ ...showBody, id: "grp-new" }));
    vi.stubGlobal("fetch", fetch);
    const r = await requestFor(missionIdReader("m"), "sc-1");
    expect(r.ok && r.value?.id).toBe("grp-new");
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
    expect(phoneGoBlocked(g, null, "user-1", true, names)).toMatch(/your own request/);
    expect(phoneGoBlocked(g, null, "user-9", true, names)).toBe("Re-checking before GO…");
    const noGo = review([{ key: "catalog", result: "no_go", per_target: [], evidence: {} }]);
    expect(phoneGoBlocked(g, noGo, "user-9", true, names)).toBe("The Catalog re-check is NO-GO.");
    expect(phoneGoBlocked(g, review([]), "user-9", true, names)).toBeNull();
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
    expect(phoneGoBlocked(one, review([]), "user-9", true, names)).toBeNull();
  });
});
