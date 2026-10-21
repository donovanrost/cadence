import { required } from "../../../../../test-support/required";
import { mount } from "@vue/test-utils";
import { pageHeaderHarness } from "@cadence/plugin-sdk/page-header-testing";
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
      total_count: 1,
      page: 1,
      page_size: 20,
      page_count: 1,
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
  const header = pageHeaderHarness("/missions/:mission_id/comms/validation");
  const wrapper = mount(CommsValidation, {
    props: readValidation(payload(), context),
    global: { provide: header.provide },
  });
  try {
    expect(wrapper.get("#transports-finding-1 a").attributes("href")).toBe(
      "/missions/mission-1/comms/transports",
    );
    expect(header.header().facts?.[0]).toBe("1 finding");
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
  required(required(input.data.finding_groups[0]).findings[0]).action_href = "//evil.example";
  expect(() => readValidation(input, context)).toThrow();
});

test("findings beyond the first page retain fleet totals and scoped navigation", () => {
  const input = payload();
  const data = { ...input.data, total_count: 41, page: 3, page_count: 3 };
  const header = pageHeaderHarness("/missions/:mission_id/comms/validation");
  const wrapper = mount(CommsValidation, {
    props: readValidation({ ...input, data }, context),
    global: { provide: header.provide },
  });
  try {
    expect(header.header().facts?.[0]).toBe("41 findings");
    expect(wrapper.get("#comms-validation-pagination").text()).toContain("41–41 of 41");
    expect(wrapper.get("#comms-validation-previous").attributes("href")).toBe(
      "/missions/mission-1/comms/validation?page=2",
    );
    expect(wrapper.find("#comms-validation-next").exists()).toBe(false);
  } finally {
    wrapper.unmount();
  }
});

test("pagination cannot hide missing findings or claim an out-of-range page", () => {
  const input = payload();
  for (const pagination of [
    { total_count: 21, page: 1, page_count: 2 },
    { total_count: 21, page: 2, page_count: 1 },
    { total_count: 21, page: 3, page_count: 2 },
    { total_count: 0, page: 1, page_count: 1 },
    { total_count: 1, page: 1, page_count: 1, page_size: 100 },
  ]) {
    expect(() =>
      readValidation({ ...input, data: { ...input.data, ...pagination } }, context),
    ).toThrow();
  }
});
