import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import type { HistoricalWorkflowProps } from "./contracts";
import { OpsDataOperations } from "../../historical-workflows";
test("legacy entries retain mission, selected group and management placement through the public owner", () => {
  const w = mount(OpsDataOperations, {
    props: { mission_id: "mission-one", mode: "manage", query: { group: "group/one" } },
  });
  expect(w.get("#history-open-workspace").attributes("href")).toBe(
    "/missions/mission-one/ops/data-operations/manage?group=group%2Fone",
  );
  expect(w.find("form").exists()).toBe(false);
  w.unmount();
});
test("legacy redirect rejects unavailable identity and unowned query fields", () => {
  const fixtures: HistoricalWorkflowProps[] = [
    { mission_id: "", mode: "reader", query: {} },
    {
      mission_id: "mission",
      mode: "manage",
      query: { group: "group", organization_id: "foreign" },
    },
    { mission_id: "mission", mode: "reader", query: { group: 27 } },
  ];
  for (const props of fixtures) {
    const w = mount(OpsDataOperations, { props });
    expect(w.find("#history-open-workspace").exists()).toBe(false);
    w.unmount();
  }
});
