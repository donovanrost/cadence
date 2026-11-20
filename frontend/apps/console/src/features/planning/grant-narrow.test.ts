import { describe, expect, it } from "vite-plus/test";
import { activeBody, grantOf } from "./grant-fixtures.ts";
import { NOTHING_NARROWER, narrowChanges, narrowDraft } from "./grant-narrow.ts";

/** U105 Narrow…: the sheet starts at what the grant allows and sends only what shrinks. */
describe("narrowing a grant", () => {
  const g = grantOf(activeBody);
  const start = narrowDraft(g);

  it("starts at the grant's own values; nothing narrower keeps Narrow off (A6/A7)", () => {
    expect(start).toEqual({
      actions: ["plan", "submit"],
      hours: "48",
      contacts: "40",
      concurrency: "2",
      days: "30",
    });
    expect(narrowChanges(g, start)).toEqual({ ok: false, why: NOTHING_NARROWER, errors: {} });
  });

  it("sends only the fields that shrink, in the server's units", () => {
    expect(narrowChanges(g, { ...start, contacts: "20", days: "7", actions: ["plan"] })).toEqual({
      ok: true,
      changes: { maximum_contacts: 20, validity_seconds: 604_800, allowed_actions: ["plan"] },
    });
    expect(narrowChanges(g, { ...start, hours: "24" })).toEqual({
      ok: true,
      changes: { maximum_horizon_seconds: 86_400 },
    });
  });

  it("never offers more: a larger value, an empty or new action, a bad number", () => {
    const more = narrowChanges(g, { ...start, contacts: "41" });
    expect(more.ok).toBe(false);
    if (!more.ok) expect(more.errors["contacts"]).toContain("To widen it, propose a new grant.");
    const none = narrowChanges(g, { ...start, actions: [] });
    if (!none.ok) expect(none.errors["actions"]).toBe("Keep at least one.");
    const added = narrowChanges(g, { ...start, actions: ["plan", "submit", "approve"] });
    expect(added.ok).toBe(false);
    const bad = narrowChanges(g, { ...start, concurrency: "1.5" });
    if (!bad.ok) expect(bad.errors["concurrency"]).toBe("Enter a whole number above 0.");
  });

  it("an action the console can't name keeps the actions as they are", () => {
    const odd = grantOf(activeBody, { allowed_actions: ["plan", "teleport"] });
    expect(narrowDraft(odd).actions).toEqual(["plan"]);
    expect(narrowChanges(odd, { ...narrowDraft(odd), actions: [], contacts: "10" })).toMatchObject({
      ok: false,
    });
    expect(narrowChanges(odd, { ...narrowDraft(odd), contacts: "10" })).toEqual({
      ok: true,
      changes: { maximum_contacts: 10 },
    });
  });
});
