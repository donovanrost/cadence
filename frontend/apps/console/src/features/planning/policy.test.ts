import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import {
  authorDecisionRefusal,
  buildDocument,
  groups,
  initialValues,
  pendingLine,
  policyReader,
  policySaveFailure,
} from "./policy.ts";

const field = (path: string, group: string, advanced: boolean, type = "integer") => ({
  path,
  label: path,
  type,
  unit: null,
  enum: null,
  range: { min: 0, max: 100 },
  default: 5,
  required: false,
  help: null,
  visible_when: null,
  group,
  advanced,
});

const result = decode(policyReader, {
  policy_id: null,
  version: null,
  active_version: null,
  document: null,
  pending: null,
  schema: [field("horizon.days", "horizon", false), field("scoring.cost_weight", "scoring", true)],
  defaults: { horizon: { days: 3 }, scoring: { cost_weight: 1 } },
  permissions: ["fleet_planning_policy.manage"],
});
if (!result.ok) throw result.error;
const policy = result.value;

describe("contact planning policy", () => {
  it("groups fields and separates advanced ones", () => {
    expect(groups(policy).map((g) => [g.key, g.fields.length, g.advanced.length])).toEqual([
      ["horizon", 1, 0],
      ["scoring", 0, 1],
    ]);
  });

  it("prefills from defaults when there's no policy and builds the grouped document", () => {
    const values = initialValues(policy);
    expect(values["horizon.days"]).toBe("3");
    expect(buildDocument(policy, { ...values, "horizon.days": "7" })).toEqual({
      ok: true,
      document: { horizon: { days: 7 }, scoring: { cost_weight: 1 } },
    });
    expect(buildDocument(policy, { ...values, "horizon.days": "700" }).ok).toBe(false);
  });
});

describe("money fields (DECISIONS #63, U34)", () => {
  const withMoney = decode(policyReader, {
    policy_id: "p",
    version: 2,
    active_version: 2,
    document: {
      budgets: { max_contacts: 40, currency: "USD", max_estimated_cost_micros: 5_000_000 },
      scoring: { cost_efficiency_weight: 100 },
    },
    pending: null,
    schema: [
      field("budgets.max_contacts", "budgets", false),
      field("budgets.currency", "budgets", false, "string"),
      field("budgets.max_estimated_cost_micros", "budgets", false),
      field("scoring.cost_efficiency_weight", "scoring", true),
    ],
    defaults: null,
    permissions: ["fleet_planning_policy.manage"],
  });
  if (!withMoney.ok) throw withMoney.error;
  const p = withMoney.value;
  it("hides them and drops a group left empty", () => {
    expect(groups(p).map((g) => [g.key, g.fields.map((f) => f.path), g.advanced.length])).toEqual([
      ["budgets", ["budgets.max_contacts"], 0],
    ]);
  });
  it("still saves their server values unchanged", () => {
    const built = buildDocument(p, initialValues(p));
    expect(built).toEqual({
      ok: true,
      document: {
        budgets: { max_contacts: 40, currency: "USD", max_estimated_cost_micros: 5_000_000 },
        scoring: { cost_efficiency_weight: 100 },
      },
    });
  });
});

describe("pending policy line (ux U20)", () => {
  const pending = { version: 4, requested_by: { name: "Mira K." }, reason: null };
  it("ends at the time without a reason, and with the reason when there is one", () => {
    expect(pendingLine(pending, "11-14 02:10Z")).toBe(
      "Policy v4 was proposed by Mira K. at 11-14 02:10Z.",
    );
    expect(pendingLine({ ...pending, reason: "Shorter passes" }, "11-14 02:10Z")).toBe(
      "Policy v4 was proposed by Mira K. at 11-14 02:10Z: Shorter passes.",
    );
    expect(pendingLine({ ...pending, reason: "Shorter passes." }, "11-14 02:10Z")).toBe(
      "Policy v4 was proposed by Mira K. at 11-14 02:10Z: Shorter passes.",
    );
  });
  it("leaves out who when the saver isn't known", () => {
    expect(pendingLine({ ...pending, requested_by: null }, "11-14 02:10Z")).toBe(
      "Policy v4 was proposed at 11-14 02:10Z.",
    );
  });
});

// ux on #653: a policy isn't a change set, so an unclear save never points at Staged changes; the
// version's author's refusal takes U95's form.
describe("policy save and decision words (ux on #653)", () => {
  it("an unclear save reloads the policy's versions; a refusal keeps failureOutcome's line", () => {
    expect(policySaveFailure({ kind: "unavailable", status: 500, message: "boom" })).toBe(
      "The server failed while answering, so it isn't clear whether this version was saved. Reload to see the policy's versions before trying again.",
    );
  });

  it("the author's own approve or reject is refused in U95's form", () => {
    expect(authorDecisionRefusal("approve")).toBe(
      "Not approved: you saved this version, so another org admin approves it. Your approval wasn't recorded.",
    );
    expect(authorDecisionRefusal("reject")).toBe(
      "Not rejected: you saved this version, so another org admin decides it. Nothing changed.",
    );
  });
});
