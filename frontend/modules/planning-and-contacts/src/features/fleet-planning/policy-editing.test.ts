import { required, emittedPolicy } from "./policy-test-helpers";
import { expect, test } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import OpsFleetPlanningPolicy from "./OpsFleetPlanningPolicy.vue";
import { admitPolicyEditReference } from "./policy-evidence";
import { editingFixture } from "./policy-editing.test-support";

test("edits emit explicit durations, optional ceilings, and the exact immutable base", async () => {
  const props = editingFixture();
  const wrapper = mount(OpsFleetPlanningPolicy, { props });
  const repair = wrapper.get("#policy-repair_horizon_duration").element as HTMLInputElement;
  expect(repair.type).toBe("text");
  expect(repair.value).toBe("1h 1s");
  await wrapper.get("#policy-max_horizon_duration").setValue("1d 2h 3m 4s");
  await wrapper.get("#fleet-policy-form").trigger("submit");
  const payload = emittedPolicy(wrapper, "save-policy");
  expect(payload.edit_reference).toEqual(required(props.policy_form).edit_reference);
  expect(payload.policy.max_horizon_duration).toBe("1d 2h 3m 4s");
  expect(payload.policy.repair_horizon_duration).toBe("1h 1s");
  expect(payload.policy.max_contacts).toBe("");
  expect(payload.policy.automatic_submission).toBe("false");
  expect(wrapper.get("#policy-max_contacts").attributes("required")).toBeUndefined();
  expect(wrapper.get("#policy-max_horizon_duration").attributes("aria-describedby")).toBe(
    "fleet-policy-duration-help",
  );
  expect(emittedPolicy(wrapper, "validate-policy")).toEqual(payload);
  wrapper.unmount();
});

test("refresh retains unsaved input and never silently rebases it onto a newer policy", async () => {
  const wrapper = mount(OpsFleetPlanningPolicy, { props: editingFixture() });
  const input = wrapper.get("#policy-requirement_concurrency").element as HTMLInputElement;
  await wrapper.get("#policy-requirement_concurrency").setValue("5");
  await wrapper.setProps(editingFixture());
  expect(input.value).toBe("5");
  await wrapper.setProps(editingFixture(2));
  expect(wrapper.get("#policy-requirement_concurrency").element).toBe(input);
  expect(input.value).toBe("5");
  expect(wrapper.get("#save-fleet-policy").attributes("disabled")).toBeDefined();
  expect(wrapper.get("#fleet-policy-edit-unavailable").text()).toContain("inputs are retained");
  await wrapper.get("#fleet-policy-form").trigger("submit");
  expect(wrapper.emitted("save-policy")).toBeUndefined();
  await wrapper.get("#fleet-policy-load-current").trigger("click");
  expect(input.value).toBe("8");
  expect(wrapper.find("#fleet-policy-edit-unavailable").exists()).toBe(false);
  await wrapper.get("#fleet-policy-form").trigger("submit");
  expect(emittedPolicy(wrapper, "save-policy", 0).edit_reference.base?.policy_version).toBe(2);
  wrapper.unmount();
});

test("clean forms follow a new base and an explicit initial reference is distinct from missing evidence", async () => {
  const wrapper = mount(OpsFleetPlanningPolicy, { props: editingFixture(null) });
  await wrapper.get("#fleet-policy-form").trigger("submit");
  expect(emittedPolicy(wrapper, "save-policy", 0).edit_reference.base).toBeNull();
  await wrapper.setProps(editingFixture(2));
  await wrapper.get("#fleet-policy-form").trigger("submit");
  expect(emittedPolicy(wrapper, "save-policy", 1).edit_reference.base?.policy_version).toBe(2);
  const bad = editingFixture(2);
  // @ts-expect-error Simulate a legacy producer omitting the required evidence.
  required(bad.policy_form).edit_reference = undefined;
  await wrapper.setProps(bad);
  await wrapper.get("#fleet-policy-form").trigger("submit");
  expect(wrapper.emitted("save-policy")).toHaveLength(2);
  expect(wrapper.get("#save-fleet-policy").attributes("disabled")).toBeDefined();
  await wrapper.setProps({ policy_form: null });
  expect(wrapper.find("#fleet-policy-form").exists()).toBe(false);
  wrapper.unmount();
});

test("unknown, malformed and cross-scope edit references are not admitted", () => {
  const reference = required(editingFixture().policy_form).edit_reference;
  const admitted = required(admitPolicyEditReference(reference));
  expect(admitted).toEqual(reference);
  expect(admitted).not.toBe(reference);
  expect(Object.isFrozen(admitted)).toBe(true);
  expect(Object.isFrozen(admitted.base)).toBe(true);
  for (const bad of [
    undefined,
    null,
    {},
    [],
    { ...reference, contract_version: 2 },
    { ...reference, extra: true },
    { ...reference, base: undefined },
    { ...reference, mission_id: "foreign" },
    { ...reference, base: { ...reference.base, content_sha256: "bad" } },
  ]) {
    expect(admitPolicyEditReference(bad)).toBeNull();
  }
});
