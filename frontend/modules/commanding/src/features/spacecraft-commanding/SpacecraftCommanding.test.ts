import {
  fixtureContext,
  fixtureRecord,
  fixtureString,
  jsonFixture,
} from "../../../../../test-support/json-fixture";
import { required } from "../../../../../test-support/required";
import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import {
  spacecraftCommandingContribution as contribution,
  SpacecraftCommanding,
} from "../../spacecraft-commanding";
import { context, spacecraftCommandingFixture as fixture } from "./fixtures.test-support";
import { readSpacecraftCommanding } from "./contracts";

test("public contribution shows exact profile and source endpoint identities with scoped monitor navigation", () => {
  const model = fixture();
  const wrapper = mount(contribution.component, { props: contribution.read(model, context) });
  expect(wrapper.get("#spacecraft-commanding-profile").text()).toBe("Pinned profile");
  expect(wrapper.text()).toContain("profile-a · v2");
  expect(wrapper.text()).toContain("Pinned bus · active");
  expect(wrapper.text()).not.toContain("Not tracked");
  expect(
    wrapper
      .get('a[href="/missions/mission-a/ops/commands?target=spacecraft_runtime%3Aspacecraft-a"]')
      .text(),
  ).toBe("Open command monitor");
  expect(wrapper.get("#commanding-edit-identity").attributes("href")).toBe(
    "/missions/mission-a/spacecraft/spacecraft-a/identity",
  );
  expect(wrapper.text()).toContain("They do not confirm command encoding");
  wrapper.unmount();
});
test("unavailable and deleted profile evidence stays distinct from an unbound spacecraft", async () => {
  const data = fixture();
  data.profile = {
    status: "unavailable",
    id: "missing-profile",
    version: 7,
    name: null,
    lifecycle: null,
    uplink: null,
    packet: null,
  };
  const wrapper = mount(contribution.component, { props: contribution.read(data, context) });
  expect(wrapper.text()).toContain("Pinned profile unavailable");
  expect(wrapper.text()).toContain("missing-profile · v7");
  expect(wrapper.text()).not.toContain("Uplink protocol");
  const unbound = fixture();
  unbound.profile = { ...data.profile, status: "unbound", id: null, version: null };
  await wrapper.setProps(contribution.read(unbound, context));
  expect(wrapper.text()).toContain("No profile selected");
  const deleted = fixture();
  deleted.profile.lifecycle = "deleted";
  await wrapper.setProps(contribution.read(deleted, context));
  expect(wrapper.get('[role="status"]').text()).toContain("pinned profile version is deleted");
  wrapper.unmount();
});
test("endpoint pages preserve search and filter submission resets the page", () => {
  const data = fixture();
  data.query = { page: 2, query: "runtime & bus" };
  data.endpoints = { page: 2, total_count: 26, items: data.endpoints.items };
  const wrapper = mount(contribution.component, { props: contribution.read(data, context) });
  expect(wrapper.text()).toContain("26 matching endpoints");
  expect(wrapper.get("nav a").attributes("href")).toBe(
    "/missions/mission-a/spacecraft/spacecraft-a/commanding?query=runtime+%26+bus",
  );
  const form = wrapper.get("form");
  expect(form.attributes("method")).toBe("get");
  expect(form.attributes("action")).toBe("/missions/mission-a/spacecraft/spacecraft-a/commanding");
  expect(form.find('[name="page"]').exists()).toBe(false);
  expect(wrapper.findAll("[data-endpoint]")).toHaveLength(1);
  wrapper.unmount();
});
test("malformed scope, profile and incomplete endpoint pages fail the public contract", () => {
  const valid = fixture();
  for (const model of [
    null,
    { ...valid, version: 2 },
    { ...valid, context: { ...context, spacecraftId: "foreign" } },
    { ...valid, profile: { ...valid.profile, version: 0 } },
    { ...valid, profile: { ...valid.profile, status: "unbound" } },
    { ...valid, endpoints: { ...valid.endpoints, total_count: 2 } },
    {
      ...valid,
      endpoints: { ...valid.endpoints, items: [{ ...valid.endpoints.items[0], id: "../foreign" }] },
    },
    { ...valid, query: { page: 1, query: " padded " } },
    { ...valid, scid: -1 },
  ]) {
    expect(() => readSpacecraftCommanding(model, context)).toThrow();
  }
});
test("legacy entry has only the owner destination and rejects forged identities", async () => {
  const wrapper = mount(SpacecraftCommanding, {
    props: { mission_id: context.missionId, spacecraft_id: context.spacecraftId },
  });
  expect(wrapper.get("a").attributes("href")).toBe(
    "/missions/mission-a/spacecraft/spacecraft-a/commanding",
  );
  expect(wrapper.find("#commanding-endpoints").exists()).toBe(false);
  await wrapper.setProps({ spacecraft_id: "../foreign" });
  expect(wrapper.find("a").exists()).toBe(false);
  wrapper.unmount();
});
test("actual producer document reaches the public component and exact endpoint monitor", () => {
  const raw = process.env.CADENCE_SPACECRAFT_COMMANDING_DOCUMENT
    ? jsonFixture(process.env.CADENCE_SPACECRAFT_COMMANDING_DOCUMENT)
    : fixture();
  const reviewedContext = fixtureRecord(raw.context);
  const data = readSpacecraftCommanding(raw, {
    ...fixtureContext(reviewedContext),
    spacecraftId: fixtureString(reviewedContext.spacecraftId),
  });
  const props = contribution.read(data, data.context);
  const wrapper = mount(contribution.component, { props });
  expect(wrapper.get("#spacecraft-commanding-page").text()).toContain(data.spacecraft_name);
  expect(wrapper.findAll("[data-endpoint]")).toHaveLength(data.endpoints.items.length);
  for (const endpoint of data.endpoints.items) {
    if (endpoint.id === "all") continue;
    const link = wrapper
      .findAll("a")
      .find(
        (a) =>
          a.text() === "Open command monitor" &&
          new URL(required(a.attributes("href")), "https://cadence.test").searchParams.get(
            "target",
          ) === endpoint.id,
      );
    expect(link).toBeDefined();
    expect(
      new URL(required(required(link).attributes("href")), "https://cadence.test").pathname,
    ).toBe(`/missions/${encodeURIComponent(data.context.missionId)}/ops/commands`);
  }
  wrapper.unmount();
});

test("profile state admission requires the actual string state", () => {
  const model = fixture();
  fixtureRecord(model).profile = {
    status: { toString: () => "unavailable" },
    id: "profile-a",
    version: 2,
    name: null,
    lifecycle: null,
    uplink: null,
    packet: null,
  };
  expect(() => readSpacecraftCommanding(model, context)).toThrow();
});
