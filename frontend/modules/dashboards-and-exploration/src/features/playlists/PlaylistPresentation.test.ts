import { fixtureRecordAt } from "../../../../../test-support/json-fixture";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import type { SettledOpsPageNavigationPort } from "@cadence/plugin-sdk/ops-pages";
import PlaylistPresentation from "./PlaylistPresentation.vue";
import { presentationFixture, playlistContext } from "./fixtures.test-support";
import { readPresentation } from "./validation";
import { snapshotFixture } from "../workspace/snapshot-fixture.test-support";
const wrappers: { unmount: () => void }[] = [];
afterEach(() => {
  wrappers.splice(0).forEach((w) => w.unmount());
  vi.useRealTimers();
  vi.restoreAllMocks();
});
function setup(playing = false, total = 2) {
  vi.useFakeTimers();
  vi.spyOn(document, "visibilityState", "get").mockReturnValue("visible");
  const model = { ...presentationFixture(), playing, total };
  const navigate = vi.fn<SettledOpsPageNavigationPort["navigate"]>().mockResolvedValue("completed"),
    refresh = vi.fn(async () => {}),
    wrapper = mount(PlaylistPresentation, {
      props: {
        model,
        context: { ...playlistContext, resourceId: "playlist-1" },
        port: { navigate },
        refresh,
      },
    });
  wrappers.push(wrapper);
  return { wrapper, navigate, refresh, model };
}
test("presentation admits only bound published snapshots and valid positions", () => {
  const model = presentationFixture(),
    context = { ...playlistContext, resourceId: "playlist-1" };
  expect(readPresentation(model, context)).toEqual(model);
  const snapshot = snapshotFixture();
  Object.assign(snapshot, {
    organization_id: "org-1",
    mission_id: "mission-1",
    dashboard_id: "dashboard-1",
  });
  model.current.snapshot = snapshot;
  expect(readPresentation(model, context)).toEqual(model);
  for (const mutate of [
    (p: unknown) => (fixtureRecordAt(p, "current", "snapshot").document_mode = "draft"),
    (p: unknown) => (fixtureRecordAt(p, "current", "snapshot").dashboard_id = "foreign"),
    (p: unknown) => (fixtureRecordAt(p).index = fixtureRecordAt(p).total),
    (p: unknown) => (fixtureRecordAt(p, "playlist").id = "foreign"),
    (p: unknown) => (fixtureRecordAt(p).total = 101),
  ]) {
    const bad = structuredClone(model);
    mutate(bad);
    expect(() => readPresentation(bad, context)).toThrow();
  }
});
test("unavailable entries keep their position and manual stepping preserves pause and wraps", async () => {
  const { wrapper, navigate } = setup();
  expect(wrapper.find("#playlist-current-unavailable").exists()).toBe(true);
  expect(wrapper.get("#playlist-position").text()).toContain("1 / 2");
  await wrapper.get("#playlist-previous").trigger("click");
  expect(navigate).toHaveBeenCalledExactlyOnceWith(
    "/missions/mission-1/ops/dashboards/playlists/playlist-1/present?index=1&playing=0",
  );
  await vi.advanceTimersByTimeAsync(60000);
  expect(navigate).toHaveBeenCalledTimes(1);
});
test("automatic rotation waits for navigation and a fresh model resets advancement", async () => {
  const { wrapper, navigate, model } = setup(true);
  navigate.mockImplementationOnce(() => new Promise(() => {}));
  await vi.advanceTimersByTimeAsync(29999);
  expect(navigate).not.toHaveBeenCalled();
  await vi.advanceTimersByTimeAsync(1);
  expect(navigate).toHaveBeenCalledExactlyOnceWith(
    "/missions/mission-1/ops/dashboards/playlists/playlist-1/present?index=1&playing=1",
  );
  await vi.advanceTimersByTimeAsync(60000);
  expect(navigate).toHaveBeenCalledTimes(1);
  expect(wrapper.find("#playlist-advancing").exists()).toBe(true);
  await wrapper.setProps({ model: { ...model, loaded_at: "2026-09-07T18:02:00Z" } });
  expect(wrapper.find("#playlist-advancing").exists()).toBe(false);
  await wrapper.get("#playlist-play-pause").trigger("click");
  await vi.advanceTimersByTimeAsync(60000);
  expect(navigate).toHaveBeenCalledTimes(1);
});
test("a single-entry playlist keeps playing without redundant navigation or locked controls", async () => {
  const { wrapper, navigate } = setup(true, 1);
  await vi.advanceTimersByTimeAsync(90_000);
  expect(navigate).not.toHaveBeenCalled();
  expect(wrapper.find("#playlist-advancing").exists()).toBe(false);
  expect(wrapper.get("#playlist-play-pause").attributes("disabled")).toBeUndefined();
  expect(wrapper.get("#playlist-play-pause").text()).toBe("Pause");
  expect(vi.getTimerCount()).toBe(1);
  await wrapper.get("#playlist-play-pause").trigger("click");
  expect(vi.getTimerCount()).toBe(0);
});
test.each(["unchanged", "cancelled", "failed"] as const)(
  "%s navigation releases controls and pauses for a deliberate retry",
  async (result) => {
    const { wrapper, navigate } = setup(true);
    navigate.mockResolvedValueOnce(result);
    await vi.advanceTimersByTimeAsync(30_000);
    expect(wrapper.find("#playlist-advancing").exists()).toBe(false);
    expect(wrapper.get("#playlist-next").attributes("disabled")).toBeUndefined();
    expect(wrapper.get("#playlist-play-pause").text()).toBe("Play");
    expect(wrapper.find("#playlist-navigation-notice").exists()).toBe(true);
    expect(vi.getTimerCount()).toBe(0);
    await wrapper.get("#playlist-next").trigger("click");
    expect(navigate).toHaveBeenCalledTimes(2);
  },
);
test("a rejected navigation promise releases controls without an unhandled rejection", async () => {
  const { wrapper, navigate } = setup(true);
  navigate.mockRejectedValueOnce(Error("Unavailable transport"));
  await vi.advanceTimersByTimeAsync(30_000);
  expect(wrapper.find("#playlist-advancing").exists()).toBe(false);
  expect(wrapper.get("#playlist-next").attributes("disabled")).toBeUndefined();
  expect(wrapper.get("#playlist-play-pause").text()).toBe("Play");
});
test("hidden and unmounted presenters stop automatic navigation", async () => {
  const { wrapper, navigate } = setup(true);
  vi.spyOn(document, "visibilityState", "get").mockReturnValue("hidden");
  document.dispatchEvent(new Event("visibilitychange"));
  await vi.advanceTimersByTimeAsync(60000);
  expect(navigate).not.toHaveBeenCalled();
  expect(wrapper.get("#playlist-play-pause").text()).toBe("Play");
  vi.spyOn(document, "visibilityState", "get").mockReturnValue("visible");
  await wrapper.get("#playlist-play-pause").trigger("click");
  wrapper.unmount();
  await vi.advanceTimersByTimeAsync(60000);
  expect(navigate).not.toHaveBeenCalled();
});
