import { readNativePolicyScenario } from "./policy-native-fixture.test-support";
import { required, emittedPolicy } from "./policy-test-helpers";
import { describe, expect, test } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import OpsFleetPlanningPolicy from "./OpsFleetPlanningPolicy.vue";
import { admitPolicyEvidence } from "./policy-evidence";
import { decisionFixture, evidenceFixture } from "./policy-decisions.test-support";

test("producer-supplied decision emits through the client-compiled Vue form", async () => {
  const input = process.env.CADENCE_FLEET_DECISION_MODEL;
  const { props, action, values } = input
    ? readNativePolicyScenario(JSON.parse(input))
    : { props: decisionFixture(), action: "approve-policy" as const, values: {} };
  const warnings: string[] = [];
  const wrapper = mount(OpsFleetPlanningPolicy, {
    props,
    global: { config: { warnHandler: (message) => warnings.push(message) } },
  });
  try {
    let formId: string;
    if (action === "save-policy") {
      const form = required(props.policy_form);
      formId = form.id;
      for (const key of ["max_horizon_duration", "repair_horizon_duration"] as const) {
        const input = wrapper.get("#" + form.fields[key].id).element as HTMLInputElement;
        expect(input.type).toBe("text");
        expect(input.value).toBe(form.fields[key].value);
      }
      for (const [key, value] of Object.entries(values)) {
        const field = required(Object.entries(form.fields).find(([name]) => name === key))[1];
        await wrapper.get("#" + field.id).setValue(value);
      }
    } else if (action === "issue-grant") {
      const form = required(props.grant_form);
      formId = form.id;
      const duration = wrapper.get("#" + form.fields.maximum_horizon_duration.id)
        .element as HTMLInputElement;
      expect(duration.type).toBe("text");
      expect(duration.value).toBe(form.fields.maximum_horizon_duration.value);
      await wrapper
        .get("#" + form.fields.approval_reason.id)
        .setValue("Reviewed exact producer evidence");
    } else {
      const form = required(props.approval_form);
      formId = form.id;
      await wrapper.get("#" + form.reason.id).setValue("Reviewed exact producer evidence");
    }
    await wrapper.get("#" + formId).trigger("submit");
    expect(warnings).toEqual([]);
    const events = wrapper.emitted(action);
    expect(events).toHaveLength(1);
    if (input)
      process.stdout.write(
        "DECISION_PAYLOAD=" + JSON.stringify(required(required(events)[0])[0]) + "\n",
      );
  } finally {
    wrapper.unmount();
  }
});

describe("reviewed policy decisions", () => {
  test("grant duration controls preserve units and whole seconds through native input", async () => {
    const props = decisionFixture();
    required(props.grant_form).fields.maximum_horizon_duration.value = "1h 1s";
    const wrapper = mount(OpsFleetPlanningPolicy, { props });
    const duration = wrapper.get("#grant-maximum_horizon_duration");
    expect((duration.element as HTMLInputElement).type).toBe("text");
    expect((duration.element as HTMLInputElement).value).toBe("1h 1s");
    expect(duration.attributes("aria-describedby")).toBe("automation-grant-duration-help");
    expect(wrapper.get("#automation-grant-duration-help").element.closest("label")).toBeNull();
    await duration.setValue("1s");
    await wrapper.get("#grant-approval_reason").setValue("One second bound");
    await wrapper.get("#automation-grant-form").trigger("submit");
    expect(emittedPolicy(wrapper, "issue-grant", 0).grant.maximum_horizon_duration).toBe("1s");
    wrapper.unmount();
  });

  test("approval and issuance emit their distinct reviewed immutable references", async () => {
    const props = decisionFixture(2, 1);
    const wrapper = mount(OpsFleetPlanningPolicy, { props });
    await wrapper.get("#fleet-policy-approval-reason").setValue("Approve this draft");
    await wrapper.get("#fleet-policy-approval-form").trigger("submit");
    expect(wrapper.emitted("approve-policy")).toEqual([
      [
        {
          decision: { reason: "Approve this draft", policy_evidence: evidenceFixture(2) },
        },
      ],
    ]);
    await wrapper.get("#grant-approval_reason").setValue("Bounded mission operations");
    await wrapper.get("#automation-grant-form").trigger("submit");
    expect(wrapper.emitted("issue-grant")).toEqual([
      [
        {
          grant: {
            service_identity_id: "service-1",
            maximum_horizon_duration: "24h",
            maximum_contacts: "10",
            maximum_execution_concurrency: "2",
            valid_days: "7",
            approval_reason: "Bounded mission operations",
          },
          policy_evidence: evidenceFixture(1),
        },
      ],
    ]);
    expect(wrapper.get("#automation-grant-policy-evidence").text()).toContain("Approved policy v1");
    expect(wrapper.get("#automation-grant-policy-evidence").text()).toContain(
      evidenceFixture(1).content_sha256,
    );
    wrapper.unmount();
  });

  test("a new reviewed version clears the old reason without replacing the native input", async () => {
    const wrapper = mount(OpsFleetPlanningPolicy, { props: decisionFixture() });
    const reason = wrapper.get("#fleet-policy-approval-reason").element as HTMLTextAreaElement;
    await wrapper.get("#fleet-policy-approval-reason").setValue("Reason for v1 only");
    await wrapper.setProps(decisionFixture());
    expect(reason.value).toBe("Reason for v1 only");
    await wrapper.setProps(decisionFixture(2, 1));
    expect(wrapper.get("#fleet-policy-approval-reason").element).toBe(reason);
    expect(reason.value).toBe("");
    await wrapper.get("#fleet-policy-approval-reason").setValue("Review v2");
    await wrapper.get("#fleet-policy-approval-form").trigger("submit");
    expect(wrapper.emitted("approve-policy")).toEqual([
      [
        {
          decision: { reason: "Review v2", policy_evidence: evidenceFixture(2) },
        },
      ],
    ]);
    wrapper.unmount();
  });

  test("approval evidence must match the displayed policy and grants must match its scope", async () => {
    const props = decisionFixture(2, 1);
    required(props.approval_form).policy_evidence = evidenceFixture(1);
    required(props.grant_form).policy_evidence = {
      ...evidenceFixture(1),
      mission_id: "another-mission",
    };
    const wrapper = mount(OpsFleetPlanningPolicy, { props });
    expect(wrapper.get("#approve-fleet-policy").attributes("disabled")).toBeDefined();
    expect(wrapper.get("#issue-automation-grant").attributes("disabled")).toBeDefined();
    expect(wrapper.find("#fleet-policy-evidence-unavailable").exists()).toBe(true);
    await wrapper.get("#fleet-policy-approval-form").trigger("submit");
    await wrapper.get("#automation-grant-form").trigger("submit");
    expect(wrapper.emitted("approve-policy")).toBeUndefined();
    expect(wrapper.emitted("issue-grant")).toBeUndefined();
    wrapper.unmount();
  });

  test("legacy or malformed decision references never emit privileged actions", async () => {
    const props = decisionFixture();
    // @ts-expect-error Simulate a legacy producer omitting the required evidence.
    required(props.approval_form).policy_evidence = undefined;
    required(props.grant_form).policy_evidence = {
      ...evidenceFixture(),
      // @ts-expect-error Simulate an incompatible evidence protocol.
      contract_version: 2,
    };
    const wrapper = mount(OpsFleetPlanningPolicy, { props });
    await wrapper.get("#fleet-policy-approval-form").trigger("submit");
    await wrapper.get("#automation-grant-form").trigger("submit");
    expect(wrapper.emitted("approve-policy")).toBeUndefined();
    expect(wrapper.emitted("issue-grant")).toBeUndefined();
    expect(wrapper.find("#fleet-policy-evidence-unavailable").exists()).toBe(true);
    await wrapper.setProps({ approval_form: null, grant_form: null });
    expect(wrapper.find("#fleet-policy-approval-form").exists()).toBe(false);
    expect(wrapper.find("#automation-grant-form").exists()).toBe(false);
    wrapper.unmount();
  });

  test("new active grant evidence retains the draft and requires an explicit reload", async () => {
    const wrapper = mount(OpsFleetPlanningPolicy, { props: decisionFixture(2, 1) });
    const reason = wrapper.get("#grant-approval_reason").element as HTMLTextAreaElement;
    await wrapper.get("#grant-approval_reason").setValue("Authority under v1");
    await wrapper.setProps(decisionFixture(2, 2));
    expect(wrapper.get("#grant-approval_reason").element).toBe(reason);
    expect(reason.value).toBe("Authority under v1");
    expect(wrapper.get("#issue-automation-grant").attributes("disabled")).toBeDefined();
    await wrapper.get("#fleet-grant-load-current").trigger("click");
    expect(reason.value).toBe("");
    await wrapper.get("#grant-approval_reason").setValue("Authority under v2");
    await wrapper.get("#automation-grant-form").trigger("submit");
    expect(emittedPolicy(wrapper, "issue-grant", 0).policy_evidence).toEqual(evidenceFixture(2));
    wrapper.unmount();
  });
});

test("policy evidence admission is exact, bounded and returns an immutable copy", () => {
  const input = evidenceFixture();
  const admitted = admitPolicyEvidence(input);
  expect(admitted).toEqual(input);
  expect(admitted).not.toBe(input);
  expect(Object.isFrozen(admitted)).toBe(true);
  for (const bad of [
    null,
    [],
    {},
    { ...input, extra: true },
    { ...input, contract_version: 2 },
    { ...input, policy_version: 0 },
    { ...input, policy_version: 1.5 },
    { ...input, policy_version: Number.MAX_SAFE_INTEGER + 1 },
    { ...input, policy_id: " " },
    { ...input, mission_id: "a".repeat(257) },
    { ...input, organization_id: "x\n" },
    { ...input, policy_id: "é".repeat(129) },
    { ...input, content_sha256: "A".repeat(64) },
    { ...input, content_sha256: input.content_sha256 + "\n" },
  ])
    expect(admitPolicyEvidence(bad)).toBeNull();
});
