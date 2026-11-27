import { flushPromises, mount, RouterLinkStub } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId } from "@/api";
import { membersQuery } from "./ephemerisMembers.ts";
import EphemerisMembers from "./EphemerisMembers.vue";

vi.mock("@/live", async (original) => ({
  ...(await original<typeof import("@/live")>()),
  useMissionInvalidation: () => undefined,
}));
afterEach(() => vi.unstubAllGlobals());

/** Synthetic fixtures in the shape setup.md gives (#972 at 2304b988c), not captured from a server. */
const member = (n: number, o: Record<string, unknown> = {}) => ({
  spacecraft: { id: `spacecraft-earendil-00${n}`, name: `EARENDIL-00${n}`, scid: n },
  reason: "provider_timeout",
  detail: "The provider didn't answer in time.",
  attempts: 3,
  next_retry_at: "2026-11-27T12:15:00Z",
  since: "2026-11-25T09:30:00Z",
  ...o,
});

function server(pages: readonly (readonly unknown[])[]) {
  const asked: URL[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn((input: string) => {
      const url = new URL(input, "http://x");
      asked.push(url);
      const at = Number(url.searchParams.get("cursor") ?? "0");
      const body = {
        data: pages[at] ?? [],
        meta: { next_cursor: at + 1 < pages.length ? String(at + 1) : null },
      };
      return Promise.resolve(new Response(JSON.stringify(body), { status: 200 }));
    }),
  );
  return asked;
}

async function mountList(
  cause: "norad_id_missing" | "failed" | "not_ready",
  reason: string | null,
) {
  const w = mount(EphemerisMembers, {
    props: { missionId: missionId("m-1"), providerId: "prov_1", cause, reason },
    global: { stubs: { RouterLink: RouterLinkStub } },
  });
  await flushPromises();
  return w;
}

describe("the member list's route query (Now's deep link)", () => {
  it("reads cause and reason; norad_id_missing has no reason; an unknown cause opens nothing", () => {
    expect(membersQuery({ cause: "failed", reason: "provider_timeout" })).toEqual({
      cause: "failed",
      reason: "provider_timeout",
    });
    expect(membersQuery({ cause: "not_ready" })).toEqual({ cause: "not_ready", reason: null });
    expect(membersQuery({ cause: "norad_id_missing", reason: "x" })).toEqual({
      cause: "norad_id_missing",
      reason: null,
    });
    expect(membersQuery({ cause: "stale" })).toBeNull();
    expect(membersQuery({})).toBeNull();
  });
});

describe("EphemerisMembers (#972)", () => {
  it("asks for the group, and shows each spacecraft linked by SCID with its own facts", async () => {
    const asked = server([[member(1), member(2, { attempts: 0, next_retry_at: null })]]);
    const w = await mountList("failed", "provider_timeout");
    expect(asked[0]?.pathname).toBe("/api/v1/missions/m-1/providers/prov_1/ephemeris/spacecraft");
    expect(Object.fromEntries(asked[0]?.searchParams ?? [])).toEqual({
      cause: "failed",
      reason: "provider_timeout",
      limit: "50",
    });
    expect(w.find("h3").text()).toBe("Spacecraft whose orbit upload is failing");
    const links = w.findAllComponents(RouterLinkStub);
    expect(links.map((l) => l.props("to"))).toEqual([
      { name: "ops.spacecraft", params: { scId: 1 } },
      { name: "ops.spacecraft", params: { scId: 2 } },
    ]);
    const rows = w.findAll("tbody tr");
    expect(rows[0]?.text()).toContain("SCID 1");
    expect(rows[0]?.text()).toContain("The provider didn't answer in time.");
    expect(rows[0]?.findAll("td").map((c) => c.text())[2]).toBe("3");
    expect(rows[1]?.findAll("td").map((c) => c.text())[2]).toBe("");
    expect(rows[1]?.text()).toContain("Not scheduled");
    expect(w.findAll("th").map((h) => h.text())).toEqual([
      "Spacecraft",
      "Why",
      "Attempts",
      "Since",
      "Next retry",
    ]);
    w.unmount();
  });

  it("pages with Load more, and names a spacecraft Cadence no longer knows honestly", async () => {
    const gone = member(9, { spacecraft: { id: "spacecraft-gone", name: null, scid: null } });
    server([[member(1)], [gone]]);
    const w = await mountList("not_ready", null);
    expect(w.findAll("th").map((h) => h.text())).toEqual([
      "Spacecraft",
      "Why",
      "Since",
      "Next check",
    ]);
    await w.find("button").trigger("click");
    await flushPromises();
    const rows = w.findAll("tbody tr");
    expect(rows).toHaveLength(2);
    expect(rows[1]?.text()).toContain("Unknown spacecraft");
    expect(rows[1]?.text()).toContain("SCID unknown");
    expect(rows[1]?.findComponent(RouterLinkStub).exists()).toBe(false);
    expect(
      w.find("button").attributes("aria-disabled") ?? w.find("button").attributes("disabled"),
    ).toBeDefined();
    w.unmount();
  });

  it("norad_id_missing: no reason columns; an emptied group says so", async () => {
    server([[member(1, { reason: null, detail: null, attempts: 0, next_retry_at: null })]]);
    const w = await mountList("norad_id_missing", null);
    expect(w.findAll("th").map((h) => h.text())).toEqual(["Spacecraft", "Since"]);
    expect(w.text()).toContain("carry no NORAD id");
    w.unmount();
    server([[]]);
    const empty = await mountList("failed", "provider_timeout");
    expect(empty.text()).toContain("No spacecraft in this group now");
    expect(empty.find("table").exists()).toBe(false);
    empty.unmount();
  });
});
