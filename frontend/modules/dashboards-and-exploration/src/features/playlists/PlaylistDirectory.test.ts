import {
  fixtureRecordAt,
  fixtureRecord,
  fixtureString,
} from "../../../../../test-support/json-fixture";
import { required } from "../../../../../test-support/required";
import type { OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import { afterEach, expect, test, vi, type Mock } from "vite-plus/test";
import { mount, flushPromises } from "@vue/test-utils";
import PlaylistDirectory from "./PlaylistDirectory.vue";
import { directoryFixture, playlistContext } from "./fixtures.test-support";
import { readState } from "./validation";
const wrappers: { unmount: () => void }[] = [];
afterEach(() => {
  wrappers.splice(0).forEach((w) => w.unmount());
  vi.unstubAllGlobals();
});
function setup(
  execute: Mock<OpsPagePort["execute"]> = vi.fn(async (): Promise<unknown> => {
    throw Error("Lost reply");
  }),
) {
  vi.stubGlobal(
    "confirm",
    vi.fn(() => false),
  );
  let guard = () => true;
  const dispose = vi.fn(),
    navigate = vi.fn((_: string) => guard());
  const state = directoryFixture(),
    wrapper = mount(PlaylistDirectory, {
      props: {
        state,
        context: playlistContext,
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
  return { wrapper, execute, navigate, canLeave: () => guard(), state };
}
async function draft(w: Pick<ReturnType<typeof mount>, "get">) {
  await w.get('[data-add-dashboard="dashboard-1"]').trigger("click");
  await w.get("#playlist-name").setValue("Flight queue");
}
const reply = (state = directoryFixture(), extra = {}) => ({
  status: "ok",
  sequence: 1,
  phase: "review",
  model: state.model,
  receipt: { id: "playlist-new", name: "Flight queue", count: 1 },
  ...extra,
});
test("directory rejects foreign identities, malformed pages and presentation state", () => {
  expect(readState(directoryFixture(), playlistContext)).toEqual(directoryFixture());
  const multi = directoryFixture();
  multi.model.playlists.rows.push({ ...required(multi.model.playlists.rows[0]), id: "second" });
  expect(readState(multi, playlistContext)).toEqual(multi);
  for (const mutate of [
    (s: unknown) => (fixtureRecordAt(s, "model").organization_id = "foreign"),
    (s: unknown) => (fixtureRecordAt(s, "model", "playlists", "rows", 0).count = 101),
    (s: unknown) => (fixtureRecordAt(s, "model", "choices", "rows", 0).published_version = 0),
    (s: unknown) => (fixtureRecordAt(s, "model", "playlists").next = "not-a-full-page"),
    (s: unknown) => (fixtureRecordAt(s).phase = "unknown"),
    (s: unknown) => (fixtureRecordAt(s, "model", "query").extra = true),
  ]) {
    const state = directoryFixture();
    mutate(state);
    expect(() => readState(state, playlistContext)).toThrow();
  }
  expect(() =>
    readState(directoryFixture(), { ...playlistContext, resourceId: "unexpected" }),
  ).toThrow();
});
test("authors order and repeat entries and creation consumes one page instance", async () => {
  const { wrapper, execute, canLeave } = setup(
    vi.fn(async () =>
      reply(directoryFixture(), { receipt: { id: "new", name: "Flight queue", count: 3 } }),
    ),
  );
  await draft(wrapper);
  await wrapper.get('[data-add-dashboard="dashboard-2"]').trigger("click");
  await wrapper.get('[data-add-dashboard="dashboard-1"]').trigger("click");
  await wrapper.get('[aria-label="Move entry 2 up"]').trigger("click");
  await wrapper.get("#playlist-create-form").trigger("submit");
  await flushPromises();
  expect(execute).toHaveBeenCalledExactlyOnceWith("create_playlist", {
    sequence: 1,
    fields: {
      name: "Flight queue",
      description: "",
      dwell_seconds: 30,
      wallboard_mode: false,
      dashboard_ids: ["dashboard-2", "dashboard-1", "dashboard-1"],
    },
  });
  expect(wrapper.get("#playlist-created-link").attributes("href")).toContain("/new/present");
  expect(canLeave()).toBe(true);
  await wrapper.get("#playlist-create-form").trigger("submit");
  expect(execute).toHaveBeenCalledTimes(1);
});
test("reordering repeated entries retains the moved entry's native controls", async () => {
  const { wrapper } = setup();
  document.body.appendChild(wrapper.element);
  await draft(wrapper);
  await wrapper.get('[data-add-dashboard="dashboard-1"]').trigger("click");
  await wrapper.get('[data-add-dashboard="dashboard-2"]').trigger("click");
  const control = wrapper.get('[aria-label="Move entry 3 up"]').element;
  (control as HTMLButtonElement).focus();
  await wrapper.get('[aria-label="Move entry 3 up"]').trigger("click");
  expect(wrapper.get('[aria-label="Move entry 2 up"]').element).toBe(control);
  expect(document.activeElement).toBe(control);
  await wrapper.get('[aria-label="Move entry 2 up"]').trigger("click");
  expect(wrapper.get('[aria-label="Move entry 1 up"]').element).toBe(control);
  expect(document.activeElement).toBe(control.closest("li"));
  expect(required(wrapper.findAll("#playlist-queue>li")[0]).text()).toContain("Thermal");
});

test("lookup preserves an ordered dirty queue and ignores stale search responses", async () => {
  const replies: ((v: unknown) => void)[] = [];
  const { wrapper, execute } = setup(vi.fn(() => new Promise((resolve) => replies.push(resolve))));
  await draft(wrapper);
  const input = wrapper.get("#playlist-name").element;
  await wrapper.get("#playlist-choice-query").setValue("first");
  await wrapper.get("#playlist-choice-search").trigger("submit");
  await wrapper.get("#playlist-choice-query").setValue("second");
  await wrapper.get("#playlist-choice-search").trigger("submit");
  const result = (q: string, id: string) => ({
    status: "ok",
    data: {
      version: 1,
      organization_id: "org-1",
      mission_id: "mission-1",
      query: { q, after: null },
      choices: { rows: [{ id, name: q, published_version: 1 }], next: null },
    },
  });
  required(replies[1])(result("second", "latest"));
  await flushPromises();
  required(replies[0])(result("first", "stale"));
  await flushPromises();
  expect(wrapper.find('[data-add-dashboard="latest"]').exists()).toBe(true);
  expect(wrapper.find('[data-add-dashboard="stale"]').exists()).toBe(false);
  expect(wrapper.get("#playlist-name").element).toBe(input);
  expect(wrapper.get("#playlist-queue").text()).toContain("Power");
  expect(execute.mock.calls.every((c) => c[0] === "search_dashboards")).toBe(true);
});
test("choice pagination stays bound to the applied search, not unsent text", async () => {
  const execute = vi.fn(async (_event: string, input: unknown) => ({
    status: "ok",
    data: {
      version: 1,
      organization_id: "org-1",
      mission_id: "mission-1",
      query: {
        q: fixtureString(fixtureRecord(input).q),
        after: fixtureRecord(input).after || null,
      },
      choices: fixtureRecord(input).after
        ? { rows: [], next: null }
        : {
            rows: Array.from({ length: 25 }, (_, i) => ({
              id: `choice-${i}`,
              name: `Power ${i}`,
              published_version: 1,
            })),
            next: "choice-24",
          },
    },
  }));
  const { wrapper } = setup(execute);
  await draft(wrapper);
  await wrapper.get("#playlist-choice-query").setValue("Power");
  await wrapper.get("#playlist-choice-search").trigger("submit");
  await flushPromises();
  await wrapper.get("#playlist-choice-query").setValue("Unsubmitted query");
  await wrapper.get("#playlist-more-choices").trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenLastCalledWith("search_dashboards", { q: "Power", after: "choice-24" });
  expect(wrapper.get("#playlist-queue").text()).toContain("Power");
});

test("unknown creation stays locked through refresh until explicit reload while retaining form identity", async () => {
  const execute = vi.fn(async (event: string) =>
    event === "reload_playlists"
      ? reply(directoryFixture(), { sequence: 2, phase: "ready", receipt: null })
      : { status: "unknown" },
  );
  const { wrapper, state, canLeave } = setup(execute);
  await draft(wrapper);
  const input = wrapper.get("#playlist-name").element;
  await wrapper.get("#playlist-create-form").trigger("submit");
  await flushPromises();
  expect(wrapper.get("#playlist-create").attributes("disabled")).toBeDefined();
  await wrapper.setProps({ state: { ...state, sequence: 1, phase: "review" } });
  expect(wrapper.get("#playlist-create").attributes("disabled")).toBeDefined();
  expect(canLeave()).toBe(false);
  await wrapper.get("#playlist-reload").trigger("click");
  await flushPromises();
  expect(wrapper.get("#playlist-create").attributes("disabled")).toBeUndefined();
  expect(wrapper.get("#playlist-name").element).toBe(input);
  expect((input as HTMLInputElement).value).toBe("Flight queue");
});
test("pending and invalid creation do not duplicate effects or discard the queue", async () => {
  let resolve!: (v: unknown) => void;
  const { wrapper, execute, canLeave } = setup(vi.fn(() => new Promise((r) => (resolve = r))));
  await draft(wrapper);
  await wrapper.get("#playlist-create-form").trigger("submit");
  await wrapper.get("#playlist-create-form").trigger("submit");
  expect(execute).toHaveBeenCalledTimes(1);
  expect(canLeave()).toBe(false);
  resolve(reply(directoryFixture(), { status: "invalid", phase: "ready", receipt: null }));
  await flushPromises();
  expect(wrapper.get("#playlist-queue").text()).toContain("Power");
  expect(wrapper.get("#playlist-create").attributes("disabled")).toBeUndefined();
  const e = new Event("beforeunload", { cancelable: true });
  window.dispatchEvent(e);
  expect(e.defaultPrevented).toBe(true);
});
