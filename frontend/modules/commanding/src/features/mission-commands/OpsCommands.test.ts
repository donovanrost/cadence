import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import { OpsCommands } from "../../mission-commands";
test("legacy commands link to the same scoped query without retaining another monitor", () => {
  const wrapper = mount(OpsCommands, {
    props: {
      mission_id: "mission/a",
      query: {
        status: "queued",
        target: "endpoint-a",
        query: "CMD-a",
        focus_command_id: "request/a",
        page: "2",
      },
    },
  });
  expect(wrapper.get("#commands-open-workspace").attributes("href")).toBe(
    "/missions/mission%2Fa/ops/commands?status=queued&target=endpoint-a&query=CMD-a&focus_command_id=request%2Fa&page=2",
  );
  expect(wrapper.findAll("form,button,[data-command-request]")).toHaveLength(0);
  wrapper.unmount();
});
test("missing, foreign path syntax and malformed queries cannot create a navigation target", () => {
  const cases: { mission_id?: string; query: unknown }[] = [
    { query: {} },
    { mission_id: "..", query: {} },
    { mission_id: "mission", query: { document: {} } },
    { mission_id: "mission", query: { status: "unknown" } },
  ];
  for (const props of cases) {
    const wrapper = mount(OpsCommands, { props });
    expect(wrapper.find("#commands-open-workspace").exists()).toBe(false);
    wrapper.unmount();
  }
});
