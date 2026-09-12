import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import SpacecraftReadiness from "./SpacecraftReadiness.vue";
import { contributionFixture, readinessFixture } from "./fixtures.test-support";
import { admitContributions, assertSpacecraftReadiness } from "./validation";

test("renders core identity and the independently admitted routing contribution", () => {
  const data = readinessFixture();
  assertSpacecraftReadiness(data);
  const wrapper = mount(SpacecraftReadiness, { props: data });
  expect(wrapper.get("#spacecraft-readiness-identity").text()).toContain("0");
  expect(wrapper.get("#readiness-contribution-0").text()).toContain("Enabled routing rules");
  expect(wrapper.get("#readiness-contribution-0 a").attributes("href")).toBe(
    "/missions/mission-a/spacecraft/craft-a/routing",
  );
  wrapper.unmount();
});

test.each([
  ["unsupported version", { version: 2 }],
  ["unknown slot", { slot: "host.arbitrary" }],
  [
    "foreign organization",
    { context: { ...contributionFixture().context, organizationId: "other" } },
  ],
  ["foreign mission", { context: { ...contributionFixture().context, missionId: "other" } }],
  ["foreign spacecraft", { context: { ...contributionFixture().context, spacecraftId: "other" } }],
  ["unsafe link", { action: { label: "Open", href: "//external.example" } }],
  ["missing status", { status: null }],
  [
    "oversized details",
    { details: Array.from({ length: 65 }, () => ({ label: "x", value: "y" })) },
  ],
  ["oversized label", { status: { tone: "ready", label: "x".repeat(4097) } }],
  [
    "false unavailable success",
    { availability: "unavailable", status: { tone: "ready", label: "Ready" } },
  ],
])("contains %s without losing the core or a valid sibling", (_name, patch) => {
  const data = readinessFixture();
  data.contributions.push({
    ...contributionFixture(),
    id: "application.telemetry_decom",
    ...patch,
  });
  assertSpacecraftReadiness(data);
  const wrapper = mount(SpacecraftReadiness, { props: data });
  expect(wrapper.find("#spacecraft-readiness-identity").exists()).toBe(true);
  expect(wrapper.get("#readiness-contribution-0").text()).toContain("Review routing");
  expect(wrapper.find("#readiness-contribution-1 [role=alert]").exists()).toBe(true);
  expect(wrapper.text()).toContain("Contribution unavailable");
  wrapper.unmount();
});

test("duplicate identities are both rejected and explicit unavailable results block a ready badge", () => {
  const data = readinessFixture();
  expect(admitContributions([contributionFixture(), contributionFixture()], data.context)).toEqual([
    null,
    null,
  ]);
  data.page.status = { tone: "ready", label: "Checks ready" };
  data.contributions = [
    {
      ...contributionFixture(),
      availability: "unavailable",
      status: { tone: "blocked", label: "Unavailable" },
      details: [],
    },
  ];
  const wrapper = mount(SpacecraftReadiness, { props: data });
  expect(wrapper.find("#readiness-contribution-0 [role=alert]").exists()).toBe(true);
  expect(wrapper.text()).not.toContain("Checks ready");
  expect(wrapper.text()).toContain("Contribution unavailable");
  wrapper.unmount();
});

test("malformed core data is rejected rather than treated as a contribution failure", () => {
  const data = readinessFixture();
  data.panels[0]!.action.href = "javascript:alert(1)";
  expect(() => assertSpacecraftReadiness(data)).toThrow();
});
