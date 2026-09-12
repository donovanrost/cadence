import { fixtureRecordAt } from "../../../../../test-support/json-fixture";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { mount } from "@vue/test-utils";
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
function setup(playing = false) {
  vi.useFakeTimers();
  vi.spyOn(document, "visibilityState", "get").mockReturnValue("visible");
  const model = { ...presentationFixture(), playing };
  const navigate = vi.fn((_: string) => {}),
    refresh = vi.fn(async () => {}),
    wrapper = mount(PlaylistPresentation, {
      props: {
        model,
        context: { ...playlistContext, resourceId: "playlist-1" },
        port: { navigate, execute: vi.fn() },
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
test("automatic rotation issues one navigation and refresh can recover a failed transition", async () => {
  const { wrapper, navigate, model } = setup(true);
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
