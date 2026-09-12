import { fixtureArrayAt, fixtureRecordAt } from "../../../../../test-support/json-fixture";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { mount, flushPromises } from "@vue/test-utils";
import DashboardActivity from "./DashboardActivity.vue";
import { readActivity } from "./validation";
import { activityContribution } from "./contribution";
import { activityContext, activityFixture, versionFixture } from "./fixtures.test-support";
import type { ActivityState } from "./contracts";
const wrappers: { unmount: () => void }[] = [];
afterEach(() => {
  wrappers.splice(0).forEach((w) => w.unmount());
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});
function setup(
  state = activityFixture(),
  execute = vi.fn(async (): Promise<unknown> => {
    throw Error("Lost response");
  }),
) {
  let guard = () => true;
  const dispose = vi.fn(),
    navigate = vi.fn();
  vi.stubGlobal(
    "confirm",
    vi.fn(() => true),
  );
  const wrapper = mount(DashboardActivity, {
    props: {
      state,
      context: activityContext,
      port: {
        execute,
        navigate,
        guardNavigation: (g: () => boolean) => {
          guard = g;
          return dispose;
        },
      },
    },
  });
  wrappers.push(wrapper);
  return { wrapper, execute, navigate, dispose, canLeave: () => guard() };
}
function reply(state: ActivityState, status = "ok", code: string | null = null) {
  return { status, code, state };
}
test("admits exact resource-bound metadata without raw documents, audit payloads or unknown versions", () => {
  const state = activityFixture();
  expect(activityContribution.read(state, activityContext).state).toEqual(state);
  for (const mutate of [
    (s: unknown) => (fixtureRecordAt(s, "model").version = 2),
    (s: unknown) => (fixtureRecordAt(s, "model").dashboard_id = "foreign"),
    (s: unknown) => (fixtureRecordAt(s, "model").document = {}),
    (s: unknown) => (fixtureRecordAt(s, "model").revision = 1.5),
    (s: unknown) => (fixtureRecordAt(s, "model", "selected").version = 2),
    (s: unknown) => fixtureArrayAt(s, "model", "versions").reverse(),
    (s: unknown) => (fixtureRecordAt(s, "model").next_version = 1),
    (s: unknown) =>
      (fixtureRecordAt(s, "model").versions = Array.from({ length: 26 }, () => versionFixture(1))),
    (s: unknown) =>
      (fixtureRecordAt(s, "model").events = [
        {
          id: "event",
          event_type: "published",
          document_version: 1,
          actor_id: null,
          occurred_at: null,
          payload: {},
        },
      ]),
  ]) {
    const bad = structuredClone(state);
    mutate(bad);
    expect(() => readActivity(bad, activityContext)).toThrow();
  }
});
test("publishes the selected immutable version with both observed concurrency preconditions", async () => {
  const next = activityFixture();
  next.sequence = 1;
  next.model.revision = 3;
  next.model.published_version = 1;
  const { wrapper, execute } = setup(
    activityFixture(),
    vi.fn(async () => reply(next)),
  );
  await wrapper.get("#activity-publish").trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenCalledExactlyOnceWith("publish_version", {
    sequence: 1,
    command: { version: 1, expected_version: 2, expected_revision: 2 },
  });
  expect(wrapper.get("#activity-outcome").text()).toContain("Selected version published");
  expect(wrapper.get("#activity-publish").attributes("disabled")).toBeDefined();
  expect(wrapper.get("#activity-restore").attributes("disabled")).toBeUndefined();
});
test("restore appends a draft and keeps publication separate", async () => {
  const next = activityFixture();
  next.sequence = 1;
  next.model.document_version = 3;
  next.model.revision = 3;
  const { wrapper } = setup(
    activityFixture(),
    vi.fn(async () => reply(next)),
  );
  await wrapper.get("#activity-restore").trigger("click");
  await flushPromises();
  expect(wrapper.get("#activity-outcome").text()).toContain("new draft");
  expect(window.confirm).toHaveBeenCalledWith(
    expect.stringContaining("published version will not change"),
  );
});
test("declined confirmations and read-only or archived history cannot write", async () => {
  const { wrapper, execute } = setup();
  vi.mocked(window.confirm).mockReturnValue(false);
  await wrapper.get("#activity-restore").trigger("click");
  expect(execute).not.toHaveBeenCalled();
  for (const patch of [{ author: false }, { archived: true }]) {
    const state = activityFixture();
    Object.assign(state.model, patch);
    const { wrapper } = setup(state);
    expect(wrapper.find("#activity-restore").exists()).toBe(false);
    expect(wrapper.find("#activity-publish").exists()).toBe(false);
    expect(wrapper.find("#activity-reload").exists()).toBe(true);
  }
});
test("pending effects guard navigation and ignore unsolicited refresh, then dispose the guard", async () => {
  let resolve!: (value: unknown) => void;
  const { wrapper, canLeave, navigate, dispose } = setup(
    activityFixture(),
    vi.fn(
      () =>
        new Promise((r) => {
          resolve = r;
        }),
    ),
  );
  await wrapper.get("#activity-restore").trigger("click");
  expect(canLeave()).toBe(false);
  const event = new Event("beforeunload", { cancelable: true });
  window.dispatchEvent(event);
  expect(event.defaultPrevented).toBe(true);
  await wrapper.get("#activity-editor").trigger("click");
  expect(navigate).not.toHaveBeenCalled();
  const refresh = activityFixture();
  refresh.model.revision = 50;
  await wrapper.setProps({ state: refresh });
  resolve(reply({ ...activityFixture(), sequence: 1, phase: "review" }, "unknown"));
  await flushPromises();
  expect(canLeave()).toBe(true);
  expect(wrapper.get("#activity-restore").attributes("disabled")).toBeDefined();
  wrapper.unmount();
  expect(dispose).toHaveBeenCalledOnce();
  wrappers.splice(wrappers.indexOf(wrapper), 1);
});
test("unknown and mismatched receipts remain locked across refresh until explicit reload", async () => {
  for (const response of [
    new Error("Lost"),
    reply({ ...activityFixture(), sequence: 1 }, "unknown"),
    reply({ ...activityFixture(), sequence: 1 }),
    reply({ ...activityFixture(), sequence: 1 }, "invalid", "untrusted"),
  ]) {
    const execute = vi.fn(async () => {
      if (response instanceof Error) throw response;
      return response;
    });
    const { wrapper } = setup(activityFixture(), execute);
    await wrapper.get("#activity-restore").trigger("click");
    await flushPromises();
    const refreshed = activityFixture();
    refreshed.sequence = 1;
    await wrapper.setProps({ state: refreshed });
    expect(wrapper.get("#activity-restore").attributes("disabled")).toBeDefined();
    execute.mockResolvedValue(reply({ ...activityFixture(), sequence: 2 }));
    await wrapper.get("#activity-reload").trigger("click");
    await flushPromises();
    expect(execute).toHaveBeenLastCalledWith("reload_activity", { sequence: 2, command: {} });
    expect(wrapper.get("#activity-restore").attributes("disabled")).toBeUndefined();
  }
});
test("known validation rejection permits correction without accepting arbitrary errors", async () => {
  const { wrapper } = setup(
    activityFixture(),
    vi.fn(async () => reply({ ...activityFixture(), sequence: 1 }, "invalid", "invalid_document")),
  );
  await wrapper.get("#activity-publish").trigger("click");
  await flushPromises();
  expect(wrapper.get("#activity-outcome").text()).toContain("readiness");
  expect(wrapper.get("#activity-publish").attributes("disabled")).toBeUndefined();
});
test("page links preserve independent selection and pagination, and navigate through the host", async () => {
  const state = activityFixture();
  state.model.query.before_event = "event/id";
  state.model.document_version = 30;
  state.model.versions = Array.from({ length: 25 }, (_, i) => versionFixture(30 - i));
  state.model.next_version = 6;
  const { wrapper, navigate } = setup(state);
  const link = wrapper.get("#activity-older-versions");
  expect(link.attributes("href")).toBe(
    "/missions/mission-1/ops/dashboards/dashboard-1/activity?version=1&before_version=6&before_event=event%2Fid",
  );
  await link.trigger("click");
  expect(navigate).toHaveBeenCalledWith(link.attributes("href"));
});
