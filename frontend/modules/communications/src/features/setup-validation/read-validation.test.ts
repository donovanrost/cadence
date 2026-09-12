import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import CommsValidation from "./CommsValidation.vue";
import { readValidation } from "./read-validation";
const context = { missionId: "mission-1" };
function payload() {
  const finding = {
    id: "finding-1",
    title: "Review transport",
    body: "Saved configuration needs review.",
    severity: "Blocking",
    action_label: "Review",
    action_href: "/missions/mission-1/comms/transports",
  };
  return {
    navigation: { fallback_href: "/missions/mission-1/comms/validation", breadcrumbs: [] },
    data: {
      title: "Validation",
      finding_count: 1,
      empty: false,
      status: "attention",
      findings: [finding],
      finding_groups: [
        {
          id: "transports",
          title: "Transports",
          description: "Transport checks",
          findings: [finding],
        },
      ],
    },
  };
}
test("validation renders actual grouped findings with bounded actions and honest setup status", () => {
  const wrapper = mount(CommsValidation, { props: readValidation(payload(), context) });
  try {
    expect(wrapper.get("#transports-finding-1 a").attributes("href")).toBe(
      "/missions/mission-1/comms/transports",
    );
    expect(wrapper.text()).toContain("1 finding");
    expect(wrapper.text()).toContain("Blocking");
    expect(wrapper.find("#comms-validation-empty").exists()).toBe(false);
  } finally {
    wrapper.unmount();
  }
});
test("inconsistent counts, hidden groups and unsafe finding actions cannot appear all clear", () => {
  const input = payload();
  expect(() =>
    readValidation({ ...input, data: { ...input.data, empty: true } }, context),
  ).toThrow();
  expect(() =>
    readValidation({ ...input, data: { ...input.data, finding_groups: [] } }, context),
  ).toThrow();
  input.data.finding_groups[0].findings[0].action_href = "//evil.example";
  expect(() => readValidation(input, context)).toThrow();
});
