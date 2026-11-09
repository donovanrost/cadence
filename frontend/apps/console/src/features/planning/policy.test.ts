import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { buildDocument, groups, initialValues, policyReader } from "./policy.ts";

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
  permissions: ["planning.edit"],
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
