import { describe, expect, it } from "vite-plus/test";
import { isPlanSuperseded, planErrorText } from "./errors.ts";

describe("planErrorText", () => {
  it("names known refusals in plain words and falls back for the rest", () => {
    expect(
      planErrorText({
        kind: "invalid",
        code: "fleet_planning_requirement_not_active",
        message: "x",
        details: null,
      }),
    ).toContain("Contact rules aren't active for this day");
    expect(
      planErrorText({ kind: "conflict", code: "plan_superseded", message: "x", details: null }),
    ).toContain("superseded and can't be submitted");
    expect(
      planErrorText({
        kind: "invalid",
        code: "something_new",
        message: "Server says no.",
        details: null,
      }),
    ).toBe("Server says no.");
  });
});

describe("isPlanSuperseded", () => {
  it("is true only for a 409 plan_superseded", () => {
    expect(
      isPlanSuperseded({ kind: "conflict", code: "plan_superseded", message: "x", details: null }),
    ).toBe(true);
    expect(
      isPlanSuperseded({ kind: "conflict", code: "plan_changed", message: "x", details: null }),
    ).toBe(false);
  });
});

describe("byAuthor (ux, api af0279d1)", () => {
  it("names a person, marks a system run as automatic, and says nothing when unknown", async () => {
    const { byAuthor } = await import("./api.ts");
    expect(byAuthor({ kind: "user", id: "u", name: "Cadence Administrator" })).toBe(
      " by Cadence Administrator",
    );
    expect(byAuthor({ kind: "system", id: null, name: "Cadence" })).toBe(
      " by Cadence (automatic repair)",
    );
    expect(byAuthor(null)).toBe("");
    // #485 (readers first): a member without a display name, or someone who isn't a member.
    expect(byAuthor({ kind: "user", id: "u", name: null })).toBe("");
    expect(byAuthor({ kind: "user", id: null, name: null })).toBe("");
    // ca-ux on #530 (U73/#371): a service identity says so, named or not.
    expect(byAuthor({ kind: "service", id: "svc_1", name: "Nightly planner" })).toBe(
      " by Nightly planner (a service identity)",
    );
    expect(byAuthor({ kind: "service", id: null, name: null })).toBe(" by a service identity");
  });
});

describe("draftedByOther (ux K1 drafter line)", () => {
  it("names someone else's or the system's draft, never your own", async () => {
    const { draftedByOther } = await import("./api.ts");
    const row = (author: Parameters<typeof draftedByOther>[0]["author"]) =>
      ({
        id: "p",
        version: 1,
        state: "draft",
        window: { from: null, to: null },
        author,
        counts: { passes: 1, minutes: 8, conflicts: 0, unsatisfied: 0 },
        ready_to_approve: true,
        updated_at: "2026-11-10T10:52:00Z",
        created_at: null,
        superseded: null,
        repair_of: null,
      }) as const;
    const mira = { kind: "user" as const, id: "user_mira", name: "Mira K." };
    expect(draftedByOther(row(mira), "user_me")).toBe("Drafted by Mira K. · updated 10:52Z");
    const created = (at: string) => ({ ...row(mira), created_at: at });
    expect(draftedByOther(created("2026-11-10T10:40:00Z"), "user_me")).toBe(
      "Drafted 10:40Z by Mira K. · updated 10:52Z",
    );
    expect(draftedByOther(created("2026-11-10T10:52:00Z"), "user_me")).toBe(
      "Drafted 10:52Z by Mira K.",
    );
    expect(draftedByOther(row(mira), "user_mira")).toBeNull();
    expect(
      draftedByOther(row({ kind: "system" as const, id: null, name: "Cadence" }), "user_me"),
    ).toBe("Drafted by Cadence (automatic draft) · updated 10:52Z");
    expect(draftedByOther(row(null), "user_me")).toBeNull();
  });
});

describe("planErrorText on an unclear outcome (qa #19)", () => {
  it("says a 5xx, a dropped connection or a garbled answer may have gone through", () => {
    const unclear = "may or may not have gone through";
    expect(planErrorText({ kind: "unavailable", status: 500, message: "x" })).toContain(unclear);
    expect(planErrorText({ kind: "unavailable", status: 0, message: "x" })).toContain(unclear);
    expect(planErrorText({ kind: "malformed", message: "x" })).toContain(unclear);
  });
});

describe("the U36 race: a version decided meanwhile", () => {
  it("names who decided when the server says", () => {
    expect(
      planErrorText({
        kind: "invalid",
        code: "contact_plan_version_already_decided",
        message: "The request could not be completed.",
        details: null,
      }),
    ).toBe("This version was already decided. Reload to see it.");
    expect(
      planErrorText({
        kind: "invalid",
        code: "contact_plan_version_already_decided",
        message: "x",
        details: { decided_by: { kind: "user", id: "u", name: "Mira K." } },
      }),
    ).toBe("This version was already decided by Mira K. Reload to see it.");
  });
});
