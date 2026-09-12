import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import CommsOverviewPage from "./CommsOverviewPage.vue";
import { overviewResponse } from "./fixtures.test-support";
import { unwrapCommsOverviewResponse } from "./validation";
test("overview rejects executable presentation attributes and excessive collections", () => {
  const response = overviewResponse();
  response.presentation.root.attrs.onclick = "run()";
  expect(() => unwrapCommsOverviewResponse(response)).toThrow();
  delete response.presentation.root.attrs.onclick;
  response.presentation.overview.transport.rows = Array.from({ length: 101 }, () => ({
    id: "row",
    display_name: "Transport",
    metadata: "",
    href: "/missions/mission-1/comms/transports/row",
  }));
  response.presentation.overview.transport.empty = false;
  expect(() => unwrapCommsOverviewResponse(response)).toThrow();
});

test("overview renders the admitted presentation without a federation runtime", () => {
  const response = overviewResponse();
  const wrapper = mount(CommsOverviewPage, {
    props: { presentation: unwrapCommsOverviewResponse(response) },
  });
  try {
    expect(wrapper.find("#comms-overview-content").exists()).toBe(true);
    expect(wrapper.find("#comms-transports").exists()).toBe(true);
    expect(wrapper.find('a[href="/missions/mission-1/comms/transports/new"]').exists()).toBe(true);
  } finally {
    wrapper.unmount();
  }
});

test("overview admission rejects unsupported versions and inconsistent empty states", () => {
  expect(() => unwrapCommsOverviewResponse({ ...overviewResponse(), queryVersion: 2 })).toThrow();
  const response = overviewResponse();
  response.presentation.overview.validation.finding_groups.push({
    id: "setup",
    title: "Setup",
    description: "Review",
    findings: [],
  });
  expect(() => unwrapCommsOverviewResponse(response)).toThrow();
});

test("overview renders grouped findings with unique identities and optional actions", () => {
  const response = overviewResponse();
  response.presentation.overview.validation.empty = false;
  response.presentation.overview.validation.finding_groups = ["spacecraft", "transport"].map(
    (id) => ({
      id,
      title: id,
      description: "Review setup",
      findings: [
        {
          id: null,
          title: "Check configuration",
          body: "Not runtime connectivity.",
          status: { tone: "attention", label: "Warning" },
        },
      ],
    }),
  );
  const wrapper = mount(CommsOverviewPage, {
    props: { presentation: unwrapCommsOverviewResponse(response) },
  });
  try {
    expect(wrapper.find("#spacecraft-finding-1").exists()).toBe(true);
    expect(wrapper.find("#transport-finding-1").exists()).toBe(true);
    const ids = wrapper.findAll("[id]").map((node) => node.attributes("id"));
    expect(new Set(ids).size).toBe(ids.length);
  } finally {
    wrapper.unmount();
  }
});
