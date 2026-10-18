import { h, type Component } from "vue";
import { required } from "../../../../../test-support/required";
import { test } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import { expect } from "vite-plus/test";
import { OpsContactRequirementList } from "../../contact-requirements";
import { requirementListFixture } from "./fixtures.test-support";
import { admitRequirementList } from "./requirement-list";

test("requirements render actual lifecycle without a fabricated progress bar", () => {
  const props = requirementListFixture();
  const wrapper = mount(OpsContactRequirementList, { props });
  expect(admitRequirementList(props)).toBe(true);
  expect(wrapper.get("#requirement-row-1").text()).toContain("Active");
  expect(wrapper.find(".w-2\\/3").exists()).toBe(false);
  expect(wrapper.get("#requirements-filter-active").attributes("href")).toBe(
    "/missions/mission-1/ops/requirements?page=1&state=active",
  );
  wrapper.unmount();
});

test("unsupported, duplicate, oversized and foreign-link DTOs are contained", () => {
  const malformed = [
    { ...requirementListFixture(), contract_version: 2 },
    { ...requirementListFixture(), pagination: null },
    {
      ...requirementListFixture(),
      requirements: Array.from({ length: 26 }, () =>
        required(requirementListFixture().requirements[0]),
      ),
    },
  ];
  const foreign = requirementListFixture();
  required(foreign.requirements[0]).detail_href =
    "/missions/foreign/ops/requirements/requirement-1";
  const duplicate = requirementListFixture();
  duplicate.requirements.push(required(duplicate.requirements[0]));
  const colliding = requirementListFixture();
  required(colliding.requirements[0]).__dom_id = colliding.page.id;
  for (const props of [...malformed, foreign, duplicate, colliding]) {
    expect(admitRequirementList(props)).toBe(false);
    // Exercise the component's unknown-data reader with deliberately malformed raw Vue props.
    const renderRawProps = (component: Component) => h(component, props);
    // oxlint-disable-next-line typescript/no-unsafe-argument -- vue-tsc checks this imported SFC constructor; the lint type service cannot resolve it.
    const wrapper = mount(() => renderRawProps(OpsContactRequirementList));
    expect(wrapper.find("#contact-requirements-unavailable").exists()).toBe(true);
    expect(wrapper.find("a").exists()).toBe(false);
    wrapper.unmount();
  }
});

test("pagination preserves the selected lifecycle in host navigation", async () => {
  const props = requirementListFixture();
  props.pagination.next_href = "/missions/mission-1/ops/requirements?page=2&state=all";
  const wrapper = mount(OpsContactRequirementList, { props });
  expect(wrapper.get("#requirements-next-page").attributes("href")).toBe(
    props.pagination.next_href,
  );
  expect(wrapper.get("#requirements-next-page").attributes("data-phx-link")).toBe("redirect");
  expect(wrapper.find("#requirements-previous-page").exists()).toBe(false);
  wrapper.unmount();
});
test("requirement identities and scoped links survive empty-to-populated updates", async () => {
  const props = requirementListFixture(),
    wrapper = mount(OpsContactRequirementList, { props });
  expect(wrapper.get("#requirement-row-1").attributes("href")).toBe(
    required(props.requirements[0]).detail_href,
  );
  await wrapper.setProps({ requirements: [] });
  expect(wrapper.find("#requirements-empty").exists()).toBe(true);
  await wrapper.setProps({ requirements: props.requirements });
  expect(wrapper.find("#requirements-empty").exists()).toBe(false);
  wrapper.unmount();
});
import { assertOwnershipOracle } from "../../ownership.test-support";
import { ownershipOracle } from "./ownership-oracle.test-support";
for (const [name, expected] of Object.entries(ownershipOracle)) {
  test(name + " preserves its pre-extraction compiled behavior and template", () => {
    assertOwnershipOracle(new URL("./" + name + ".vue", import.meta.url), expected, (source) => {
      if (name === "OpsContactRequirementTemplate") {
        const addition =
          '\n                    :step="template_form.fields.anchor_at.step ?? undefined"';
        expect(source.split(addition)).toHaveLength(2);
        expect(source.split('\n                    maxlength="120"')).toHaveLength(2);
        expect(source.split('\n                maxlength="2000"')).toHaveLength(2);
        return source
          .replace(addition, "")
          .replace('\n                    maxlength="120"', "")
          .replace('\n                maxlength="2000"', "");
      }
      if (name !== "OpsContactRequirementNew") return source;
      // Peel the explicit date-resolution and mobile grid sizing fixes only.
      expect(source.match(/                step="1"/g)).toHaveLength(2);
      expect(source.match(/class="grid grid-cols-1 gap-x-5/g)).toHaveLength(3);
      expect(
        source.match(/w-full min-w-0 max-w-full input px-2 text-xs sm:px-3 sm:text-sm/g),
      ).toHaveLength(2);
      expect(source.match(/fieldset mb-3 min-w-0 \[&>label\]:min-w-0/g)).toHaveLength(2);
      expect(source.match(/p-3 sm:p-5 md:grid-cols-2/g)).toHaveLength(3);
      return source
        .replace(/\n                step="1"/g, "")
        .replace(/class="grid grid-cols-1 gap-x-5/g, 'class="grid gap-x-5')
        .replace(/fieldset mb-3 min-w-0 \[&>label\]:min-w-0/g, "fieldset mb-3")
        .replace(/p-3 sm:p-5 md:grid-cols-2/g, "p-5 md:grid-cols-2")
        .replace(
          /w-full min-w-0 max-w-full input px-2 text-xs sm:px-3 sm:text-sm/g,
          "w-full input",
        );
    });
  });
}
