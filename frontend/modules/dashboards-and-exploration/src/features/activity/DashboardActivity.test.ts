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
test("history is read-only: no publish or restore controls, and versions live on the dashboard", () => {
  const { wrapper } = setup();
  expect(activityContribution.actions).toEqual(["reload_activity"]);
  expect(wrapper.find("#activity-publish").exists()).toBe(false);
  expect(wrapper.find("#activity-restore").exists()).toBe(false);
  expect(wrapper.text()).toContain("Every save is the current version");
});
test("a pending reload guards navigation, ignores unsolicited refresh, then disposes the guard", async () => {
  let resolve!: (value: unknown) => void;
  const { wrapper, canLeave, dispose } = setup(
    activityFixture(),
    vi.fn(
      () =>
        new Promise((r) => {
          resolve = r;
        }),
    ),
  );
  await wrapper.get("#activity-reload").trigger("click");
  expect(canLeave()).toBe(false);
  const event = new Event("beforeunload", { cancelable: true });
  window.dispatchEvent(event);
  expect(event.defaultPrevented).toBe(true);
  const refresh = activityFixture();
  refresh.model.revision = 50;
  await wrapper.setProps({ state: refresh });
  resolve(reply({ ...activityFixture(), sequence: 1 }));
  await flushPromises();
  expect(canLeave()).toBe(true);
  wrapper.unmount();
  expect(dispose).toHaveBeenCalledOnce();
  wrappers.splice(wrappers.indexOf(wrapper), 1);
});
test("reload is sequence-bound and reports an unconfirmed outcome", async () => {
  const execute = vi.fn(async (): Promise<unknown> => reply({ ...activityFixture(), sequence: 7 }));
  const { wrapper } = setup(activityFixture(), execute);
  await wrapper.get("#activity-reload").trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenLastCalledWith("reload_activity", { sequence: 1, command: {} });
  expect(wrapper.get("#activity-outcome").text()).toContain("could not be reloaded");
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
