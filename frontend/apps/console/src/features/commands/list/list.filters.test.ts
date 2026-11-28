import { flushPromises } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { effectScope, ref } from "vue";
import { missionId } from "@/api/index.ts";
import { emptyLine, filtersOf, qProblem, resultLine, withFilter } from "./filters.ts";

vi.mock("@/live/index.ts", async (original) => ({
  ...(await original<typeof import("@/live/index.ts")>()),
  useMissionInvalidation: () => undefined,
}));

const nameOf = (id: string) => (id === "sc-312" ? "EARENDIL-312" : id);
const row = (id: string) => ({
  id,
  state: "queued",
  title: `t-${id}`,
  requested_by: { actor_kind: "user", user_id: "u" },
  requested_at: "2026-11-09T15:26:26Z",
  requested_approver_user_id: null,
  member_count: 1,
  target_count: 1,
  command_count: 1,
  second_go_required: false,
  awaiting_me: false,
  operation_id: null,
});
const page = (ids: string[], next: string | null) =>
  Response.json({ data: { groups: ids.map(row) }, meta: { next_cursor: next } });

afterEach(() => vi.unstubAllGlobals());

describe("Commands filters (ux U69 A5a, U72)", () => {
  it("reads the URL and words the result line by what's known", () => {
    const f = filtersOf({
      q: " heater ",
      target: "sc-312",
      stage: "release_failed,indeterminate,x",
    });
    expect(f).toEqual({
      q: "heater",
      target: "sc-312",
      stages: ["release_failed", "indeterminate"],
      withdrawnRevision: null,
    });
    expect(resultLine(f, 12, true, nameOf)).toBe(
      "12 shown · Release failed, Outcome unclear · matching “heater” · on EARENDIL-312",
    );
    expect(resultLine(filtersOf({ stage: "verify_failed" }), 3, false, nameOf)).toBe(
      "3 commands · Verify failed",
    );
    expect(emptyLine(filtersOf({ stage: "release_failed", q: "heater" }), nameOf)).toBe(
      "No commands match: Release failed · “heater”.",
    );
    // E2 (#546): a withdrawn revision's "50 of N" link opens the list on its waiting groups.
    const w = filtersOf({
      withdrawn_revision: "mission_model_revision:r3",
      stage: "queued_for_contact",
    });
    expect(w.withdrawnRevision).toBe("mission_model_revision:r3");
    expect(resultLine(w, 50, true, nameOf)).toBe(
      "50 shown · Queued for AOS · on craft whose model approval was withdrawn",
    );
    expect(qProblem("x".repeat(101))).toBe("Keep the search under 100 characters.");
    expect(withFilter({ tab: "closed", q: "a" }, "q", null)).toEqual({ tab: "closed" });
  });
});

describe("Commands pages (A5c)", () => {
  it("sends the filters, loads more by cursor, dedupes moved rows", async () => {
    const fetchMock = vi
      .fn((_url: string) => Promise.resolve(page(["a", "b"], "c1")))
      .mockImplementationOnce(() => Promise.resolve(page(["a", "b"], "c1")))
      .mockImplementationOnce(() => Promise.resolve(page(["b", "c"], null)));
    vi.stubGlobal("fetch", fetchMock);
    const { useGroupPages } = await import("./useGroupPages.ts");
    const scope = effectScope();
    const pages = scope.run(() =>
      useGroupPages(ref(missionId("m")), ref(filtersOf({ q: "heater", stage: "in_flight" }))),
    );
    await flushPromises();
    expect(String(fetchMock.mock.calls[0]?.[0])).toContain("limit=100&q=heater&stage=in_flight");
    await pages?.more();
    expect(String(fetchMock.mock.calls[1]?.[0])).toContain("cursor=c1");
    const s = pages?.state.value;
    expect(s?.status === "ready" ? s.value.items.map((r) => r.id) : null).toEqual(["a", "b", "c"]);
    expect(s?.status === "ready" ? s.value.next : "x").toBeNull();
    scope.stop();
  });
});
