import { fixtureString } from "../../../../../test-support/json-fixture";
import { required } from "../../../../../test-support/required";
import { fixtureArrayAt, fixtureRecordAt } from "../../../../../test-support/json-fixture";
import { mount, flushPromises } from "@vue/test-utils";
import { test, expect, vi } from "vite-plus/test";
import CommandStages from "./CommandStages.vue";
import { directoryFixture } from "./fixtures.test-support";
import { readDirectory } from "./contracts";
test("private ownership, versions and page continuation fail closed", () => {
  const directory = directoryFixture();
  expect(readDirectory({ directory }, directory.context)).toEqual(directory);
  for (const change of [
    (d: unknown) => (fixtureRecordAt(d).version = 2),
    (d: unknown) => (fixtureRecordAt(d, "context").missionId = "other"),
    (d: unknown) => (fixtureRecordAt(d, "stages", "entries", 0).owner_id = "other"),
    (d: unknown) => (fixtureRecordAt(d, "stages").next_after = "stage_one"),
    (d: unknown) =>
      fixtureArrayAt(d, "stages", "entries").push(fixtureArrayAt(d, "stages", "entries")[0]),
  ]) {
    const d = structuredClone(directory);
    change(d);
    expect(() => readDirectory({ directory: d }, directory.context)).toThrow();
  }
});
test("directory controls preserve scoped IDs, literal searches and modifier navigation", async () => {
  const directory = directoryFixture(),
    navigate = vi.fn(),
    read = vi.fn(async () => ({ directory }));
  const w = mount(CommandStages, { props: { directory, port: { navigate }, readPort: { read } } });
  try {
    await w.get('[data-stage-id="stage_one"]').trigger("click", { ctrlKey: true });
    expect(navigate).not.toHaveBeenCalled();
    await w.get('[data-stage-id="stage_one"]').trigger("click");
    expect(navigate).toHaveBeenCalledWith("/missions/mission_one/ops/commands/stages/stage_one");
    await w.get("#stage-directory-query").setValue("100% flight");
    await w.get("#stage-directory-state").setValue("draft");
    await w.get("#stage-directory-filters").trigger("submit");
    const url = new URL(fixtureString(required(navigate.mock.calls.at(-1))[0]), "http://localhost");
    expect(url.searchParams.get("query")).toBe("100% flight");
    expect(url.searchParams.get("state")).toBe("draft");
    await w.get("#stage-directory-refresh").trigger("click");
    await flushPromises();
    expect(read).toHaveBeenCalledOnce();
  } finally {
    w.unmount();
  }
});
test("a refreshed directory cannot switch its captured actor", async () => {
  const directory = directoryFixture();
  const other = structuredClone(directory);
  other.actor_id = "other";
  other.stages.entries = [];
  const w = mount(CommandStages, {
    props: {
      directory,
      port: { navigate: vi.fn() },
      readPort: { read: vi.fn(async () => ({ directory: other })) },
    },
  });
  try {
    await w.get("#stage-directory-refresh").trigger("click");
    await flushPromises();
    expect(w.find('[data-stage-id="stage_one"]').exists()).toBe(true);
    expect(w.get('[role="alert"]').text()).toContain("could not be refreshed");
  } finally {
    w.unmount();
  }
});
