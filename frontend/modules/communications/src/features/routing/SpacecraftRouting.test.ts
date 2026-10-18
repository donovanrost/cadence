import { required } from "../../../../../test-support/required";
import { mount } from "@vue/test-utils";
import { pageHeaderHarness } from "@cadence/plugin-sdk/page-header-testing";
import { expect, test } from "vite-plus/test";
import SpacecraftRouting from "./SpacecraftRouting.vue";
import { readSpacecraftRouting } from "./spacecraft-routing.validation";
import {
  spacecraftRoutingFixture,
  spacecraftRoutingContext as context,
} from "./spacecraft-routing.test-support";

test.each([false, true])("renders a scoped routing page, empty=%s", (empty) => {
  const header = pageHeaderHarness("/missions/:mission_id/spacecraft/:spacecraft_id/routing");
  const wrapper = mount(SpacecraftRouting, {
    props: readSpacecraftRouting(spacecraftRoutingFixture(empty), context),
    global: { provide: header.provide },
  });
  expect(header.href("new-spacecraft-routing-rule-link")).toBe(
    "/missions/mission-1/comms/routing/new?spacecraft_id=spacecraft-1",
  );
  if (!empty) {
    expect(wrapper.get("#spacecraft-routing-rule-rule-1").attributes("href")).toBe(
      "/missions/mission-1/comms/routing/rule-1",
    );
    expect(wrapper.get("#spacecraft-routing-rule-rule-1").text()).toContain("Flight TCP · v1");
  } else expect(wrapper.find("#spacecraft-routing-rules").exists()).toBe(false);
  wrapper.unmount();
});
test("rejects foreign resource navigation, duplicate rules and missing transport pins", () => {
  for (const field of ["missionId", "spacecraftId"] as const)
    expect(() =>
      readSpacecraftRouting(spacecraftRoutingFixture(), { ...context, [field]: "other" }),
    ).toThrow();
  const wrong = spacecraftRoutingFixture();
  required(wrong.page.rows[0]).href = "https://outside.test";
  expect(() => readSpacecraftRouting(wrong, context)).toThrow();
  const duplicate = spacecraftRoutingFixture();
  duplicate.page.rows.push(required(duplicate.page.rows[0]));
  expect(() => readSpacecraftRouting(duplicate, context)).toThrow();
  const missing = spacecraftRoutingFixture();
  required(missing.page.rows[0]).transport_version = 0;
  expect(() => readSpacecraftRouting(missing, context)).toThrow();
});
