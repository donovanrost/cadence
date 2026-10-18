import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import SharedViewLegacyRedirect from "./SharedViewLegacyRedirect.vue";

test.each(["share", "snapshot"] as const)(
  "preserves supported long mission and %s identities",
  (kind) => {
    for (const length of [120, 121, 149, 256]) {
      const mission = "m".repeat(length),
        id = "s".repeat(length);
      const wrapper = mount(SharedViewLegacyRedirect, {
        props: { mission_id: mission, [`${kind}_id`]: id },
      });
      expect(wrapper.get("#shared-view-open-workspace").attributes("href")).toBe(
        `/missions/${mission}/ops/dashboard-${kind}s/${id}`,
      );
      wrapper.unmount();
    }
  },
);

test.each([
  "",
  "x".repeat(257),
  ".",
  "..",
  "../forged",
  "bad\\path",
  "bad\nidentity",
  "bad\u0000identity",
  "bad?query",
  "bad#fragment",
])("neither shared-view kind accepts malformed identities: %j", (id) => {
  for (const kind of ["share", "snapshot"]) {
    const wrapper = mount(SharedViewLegacyRedirect, {
      props: { mission_id: "mission", [`${kind}_id`]: id },
    });
    expect(wrapper.find("a").exists()).toBe(false);
    wrapper.unmount();
  }
});

test("invalid mission replacement removes an existing long-ID destination", async () => {
  const wrapper = mount(SharedViewLegacyRedirect, {
    props: { mission_id: "m".repeat(256), snapshot_id: "s".repeat(256) },
  });
  expect(wrapper.find("a").exists()).toBe(true);
  await wrapper.setProps({ mission_id: "m".repeat(257) });
  expect(wrapper.find("a").exists()).toBe(false);
  wrapper.unmount();
});
