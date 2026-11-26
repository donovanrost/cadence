import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { decode } from "@/api";
import { settingsReader, type SettingsSection } from "./api.ts";
import { grantRow, suspendLead, suspensionsOf, type Suspensions } from "./suspensions.ts";
import { useSectionSave } from "./useSectionSave.ts";

/** #499 (api) with ca-ux's U105 words (#507): the settings save that suspends grants. */
const grant = (id: string, service: string | null, mission = "m-1", missionName = "EARENDIL") => ({
  id,
  mission: { id: mission, name: missionName },
  service: { id: `svc-${id}`, name: service },
  allowed_actions: ["plan", "submit"],
  valid_until: "2026-12-19T06:40:00Z",
});
const refusal = (grants: readonly unknown[], digest = "d1") => ({
  error: {
    code: "approval_tightening_suspends_grants",
    message: "x",
    details: { grants, digest },
  },
});
const read = (grants: readonly unknown[]): Suspensions => {
  const s = suspensionsOf({
    kind: "conflict",
    code: "approval_tightening_suspends_grants",
    message: "x",
    details: { grants, digest: "d1" },
  });
  if (!s) throw new Error("unread");
  return s;
};

describe("the lead (U105)", () => {
  it("names up to three, then 'and N more'; one grant names its service twice", () => {
    expect(suspendLead(read([grant("a", "Nightly planner")]), false)).toBe(
      "Saving this suspends 1 automation grant: Nightly planner. Until a second org admin resumes it, Nightly planner can't act under it.",
    );
    const three = read([
      grant("a", "Nightly planner"),
      grant("b", "Relay sync"),
      grant("c", "Ops bot"),
    ]);
    expect(suspendLead(three, false)).toBe(
      "Saving this suspends 3 automation grants: Nightly planner, Relay sync and Ops bot. Until a second org admin resumes each, its service can't act under it.",
    );
    const five = read(["a", "b", "c", "d", "e"].map((x) => grant(x, x.toUpperCase())));
    expect(suspendLead(five, false)).toContain(": A, B, C and 2 more.");
  });

  it("says 'Unknown service identity' for a nameless service, never its id", () => {
    const lead = suspendLead(read([grant("a", null)]), false);
    expect(lead).toContain("Unknown service identity");
    expect(lead).not.toContain("svc-a");
  });

  it("at organization level counts missions and names each service once, by id", () => {
    const twice = {
      ...grant("b", "Nightly planner", "m-2", "TINUVIEL"),
      service: { id: "svc-a", name: "Nightly planner" },
    };
    const nameless1 = { ...grant("c", null, "m-1"), service: { id: "svc-x", name: null } };
    const nameless2 = { ...grant("d", null, "m-2"), service: { id: "svc-y", name: null } };
    const s = read([grant("a", "Nightly planner"), twice, nameless1, nameless2]);
    expect(suspendLead(s, true)).toBe(
      "Saving this suspends 4 automation grants on 2 missions: Nightly planner (2 missions), Unknown service identity and Unknown service identity. Until a second org admin resumes each, its service can't act under it.",
    );
  });

  it("lists each grant with U105's action words, the mission first at organization level", () => {
    const g = read([{ ...grant("a", "Nightly planner"), allowed_actions: ["plan", "execute"] }])
      .grants[0];
    if (!g) throw new Error("no grant");
    expect(grantRow(g, false, "12-19 06:40Z")).toBe(
      "Nightly planner · plan, book · until 12-19 06:40Z",
    );
    expect(grantRow(g, true, "12-19 06:40Z")).toBe(
      "EARENDIL · Nightly planner · plan, book · until 12-19 06:40Z",
    );
  });
});

describe("the save holds, then resends with the digest", () => {
  afterEach(() => vi.unstubAllGlobals());

  const section = (): SettingsSection => {
    const r = decode(settingsReader, {
      sections: [
        {
          key: "cadence.governance",
          title: "Governance",
          purpose: null,
          locked: false,
          version: { version: 3, at: "2026-11-19T22:00:00Z", actor: null },
          fields: [],
        },
      ],
      permissions: ["settings.edit"],
    });
    const s = r.ok ? r.value.sections[0] : undefined;
    if (!s) throw new Error("fixture");
    return s;
  };
  type FetchMock = ReturnType<typeof vi.fn<(url: string, init?: RequestInit) => Promise<Response>>>;
  /** The JSON body of the nth request. */
  const sent = (fetch: FetchMock, n: number): unknown => {
    const body = fetch.mock.calls[n]?.[1]?.body;
    if (typeof body !== "string") throw new Error("no body");
    const parsed: unknown = JSON.parse(body);
    return parsed;
  };
  const json = (body: unknown, status: number) =>
    new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

  it("holds a refused save with nothing written; confirm resends the digest; a changed list holds again", async () => {
    const fetch = vi.fn<(url: string, init?: RequestInit) => Promise<Response>>();
    fetch
      .mockResolvedValueOnce(json(refusal([grant("a", "Nightly planner")], "d1"), 409))
      .mockResolvedValueOnce(
        json(refusal([grant("a", "Nightly planner"), grant("b", "Relay sync")], "d2"), 409),
      )
      .mockResolvedValueOnce(json({ data: { version: 4 } }, 201));
    vi.stubGlobal("fetch", fetch);
    const saved = vi.fn();
    const s = useSectionSave(() => ({ kind: "mission", id: "m-1" }), section, saved);

    await s.save({ approval_requirement: "independent" });
    expect(s.pending.value?.suspensions.digest).toBe("d1");
    expect(s.pending.value?.changed).toBe(false);
    expect(s.note.value).toBeNull();
    expect(saved).not.toHaveBeenCalled();

    s.confirmSuspension();
    await vi.waitFor(() => expect(fetch).toHaveBeenCalledTimes(2));
    expect(sent(fetch, 1)).toMatchObject({
      values: { approval_requirement: "independent" },
      acknowledged_suspensions: "d1",
    });
    await vi.waitFor(() => expect(s.pending.value?.suspensions.digest).toBe("d2"));
    expect(s.pending.value?.changed).toBe(true);

    s.confirmSuspension();
    await vi.waitFor(() => expect(saved).toHaveBeenCalledOnce());
    expect(sent(fetch, 2)).toMatchObject({ acknowledged_suspensions: "d2" });
    expect(s.pending.value).toBeNull();
    expect(s.note.value?.text).toBe("Saved as v4. It's active now.");
  });

  it("a new save replaces a held one (api-ops, #510)", async () => {
    const fetch = vi.fn<(url: string, init?: RequestInit) => Promise<Response>>();
    fetch
      .mockResolvedValueOnce(json(refusal([grant("a", "Nightly planner")]), 409))
      .mockResolvedValueOnce(json({ data: { version: 4 } }, 201));
    vi.stubGlobal("fetch", fetch);
    const s = useSectionSave(() => ({ kind: "mission", id: "m-1" }), section, vi.fn());
    await s.save({ approval_requirement: "independent" });
    expect(s.pending.value).not.toBeNull();
    await s.save({ other_field: 1 });
    expect(s.pending.value).toBeNull();
    expect(sent(fetch, 1)).not.toHaveProperty("acknowledged_suspensions");
  });

  it("Cancel drops the held save; nothing more is sent", async () => {
    const fetch = vi.fn<(url: string, init?: RequestInit) => Promise<Response>>();
    fetch.mockResolvedValueOnce(json(refusal([grant("a", "Nightly planner")]), 409));
    vi.stubGlobal("fetch", fetch);
    const s = useSectionSave(() => ({ kind: "mission", id: "m-1" }), section, vi.fn());
    await s.save({ approval_requirement: "independent" });
    s.cancelSuspension();
    expect(s.pending.value).toBeNull();
    expect(fetch).toHaveBeenCalledOnce();
  });
});
