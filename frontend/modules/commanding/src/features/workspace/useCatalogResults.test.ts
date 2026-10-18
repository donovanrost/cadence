import { defineComponent, h, shallowRef, ref } from "vue";
import { mount, flushPromises } from "@vue/test-utils";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { required } from "../../../../../test-support/required";
import {
  readQuery,
  type Catalog,
  type Query,
  type Command,
} from "../../shared/command-draft/contracts";
import { workspaceFixture } from "./fixtures.test-support";
import { useCatalogResults } from "./useCatalogResults";

const cleanups: (() => void)[] = [];
afterEach(() => {
  cleanups.splice(0).forEach((cleanup) => cleanup());
  vi.useRealTimers();
});
const commands = Array.from({ length: 64 }, (_, i) => ({
  id: `command_${String(i).padStart(3, "0")}`,
  name: `COMMAND_${i}`,
  display_name: null,
}));
function result(catalog: Catalog, query: Query) {
  const matches = commands.filter(
    (row) => row.id > query.command_after && row.name.includes(query.command_query),
  );
  return {
    status: "catalog_page",
    spacecraft: [],
    catalog: {
      ...catalog,
      query,
      commands: {
        limit: 25,
        entries: matches.slice(0, 25),
        next_after: matches.length > 25 ? (matches[24]?.id ?? null) : null,
      },
    },
  };
}
function setup() {
  vi.useFakeTimers();
  const initial = required(workspaceFixture().catalog);
  const catalog = shallowRef<Catalog | null>({
    ...initial,
    commands: {
      limit: 25,
      entries: commands.slice(0, 25),
      next_after: required(commands[24]).id,
    },
  });
  const blocked = ref(false);
  const execute = vi.fn<(event: string, input: Record<string, unknown>) => Promise<unknown>>(
    async (_, input) => result(required(catalog.value), readQuery(input.query)),
  );
  let results: ReturnType<typeof useCatalogResults<Command>> | undefined;
  const wrapper = mount(
    defineComponent({
      setup() {
        results = useCatalogResults({
          catalog,
          blocked,
          port: { execute, navigate: vi.fn(), guardNavigation: () => () => {} },
          context: initial.context,
          actor: initial.actor_id,
          queryKey: "command_query",
          afterKey: "command_after",
          pick: (page) => page.commands,
          onSpacecraft: vi.fn(),
          onStale: vi.fn(async () => {}),
        });
        return () => h("div");
      },
    }),
  );
  cleanups.push(() => wrapper.unmount());
  return { results: required(results), catalog, blocked, execute, wrapper };
}
test("appends bounded pages once, keeps them across live snapshots and stops at the end", async () => {
  const c = setup();
  c.results.loadMore();
  c.results.loadMore();
  await flushPromises();
  expect(c.execute).toHaveBeenCalledTimes(1);
  expect(c.results.state.value.entries).toHaveLength(50);
  c.catalog.value = { ...required(c.catalog.value) };
  await flushPromises();
  expect(c.results.state.value.entries).toHaveLength(50);
  c.results.loadMore();
  await flushPromises();
  expect(c.results.state.value.entries).toEqual(commands);
  expect(c.results.state.value.hasMore).toBe(false);
  c.results.loadMore();
  expect(c.execute).toHaveBeenCalledTimes(2);
});
test("debounces typing, searches the whole catalog and ignores an older page", async () => {
  const c = setup();
  let resolveOld: (value: unknown) => void = () => {};
  c.execute.mockImplementationOnce(
    () =>
      new Promise((resolve) => {
        resolveOld = resolve;
      }),
  );
  c.results.loadMore();
  c.results.search("COMMAND_6");
  c.results.search("COMMAND_63");
  await vi.advanceTimersByTimeAsync(199);
  expect(c.execute).toHaveBeenCalledTimes(1);
  await vi.advanceTimersByTimeAsync(1);
  expect(c.results.state.value.entries).toEqual([commands[63]]);
  const old = readQuery(required(c.execute.mock.calls[0])[1].query);
  resolveOld(result(required(c.catalog.value), old));
  await flushPromises();
  expect(c.results.state.value.query).toBe("COMMAND_63");
  expect(c.results.state.value.entries).toEqual([commands[63]]);
});
test("waits for a write to finish and retries a failed page without dropping loaded results", async () => {
  const c = setup();
  c.blocked.value = true;
  c.results.search("COMMAND");
  await vi.advanceTimersByTimeAsync(200);
  expect(c.execute).not.toHaveBeenCalled();
  c.blocked.value = false;
  await flushPromises();
  c.execute.mockRejectedValueOnce(Error("Connection lost"));
  c.results.loadMore();
  await flushPromises();
  expect(c.results.state.value.error).not.toBe("");
  expect(c.results.state.value.entries).toHaveLength(25);
  c.results.loadMore();
  expect(c.execute).toHaveBeenCalledTimes(2);
  c.results.retry();
  await flushPromises();
  expect(c.results.state.value.entries).toHaveLength(50);
  expect(c.results.state.value.error).toBe("");
});
test("catalog replacement resets cursors and unmount cancels pending searches", async () => {
  const c = setup();
  c.results.loadMore();
  await flushPromises();
  const catalog = required(c.catalog.value);
  c.catalog.value = { ...catalog, basis: { ...catalog.basis, token: "f".repeat(64) } };
  await flushPromises();
  expect(c.results.state.value.entries).toHaveLength(25);
  c.results.search("COMMAND_63");
  c.wrapper.unmount();
  await vi.advanceTimersByTimeAsync(200);
  expect(c.execute).toHaveBeenCalledTimes(1);
});
test("rejects responses with another actor or query and ignores completion after unmount", async () => {
  const c = setup();
  c.execute.mockImplementationOnce(async (_, input) => {
    const response = result(required(c.catalog.value), readQuery(input.query));
    return { ...response, catalog: { ...response.catalog, actor_id: "another_actor" } };
  });
  c.results.loadMore();
  await flushPromises();
  expect(c.results.state.value.entries).toHaveLength(25);
  expect(c.results.state.value.error).not.toBe("");
  c.execute.mockImplementationOnce(async () =>
    result(required(c.catalog.value), required(c.catalog.value).query),
  );
  c.results.retry();
  await flushPromises();
  expect(c.results.state.value.entries).toHaveLength(25);
  let complete: (value: unknown) => void = () => {};
  c.execute.mockImplementationOnce(
    () =>
      new Promise((resolve) => {
        complete = resolve;
      }),
  );
  c.results.retry();
  const request = readQuery(required(c.execute.mock.calls[2])[1].query);
  c.wrapper.unmount();
  complete(result(required(c.catalog.value), request));
  await flushPromises();
  expect(c.results.state.value.entries).toHaveLength(25);
});

test("selecting a spacecraft leaves the mission-wide endpoint list and scroll position intact", async () => {
  const initial = required(workspaceFixture().catalog);
  const catalog = shallowRef<Catalog | null>(initial);
  let results: ReturnType<typeof useCatalogResults> | undefined;
  const wrapper = mount(
    defineComponent({
      setup() {
        results = useCatalogResults({
          catalog,
          blocked: ref(false),
          port: { execute: vi.fn(), navigate: vi.fn(), guardNavigation: () => () => {} },
          context: initial.context,
          actor: initial.actor_id,
          queryKey: "target_query",
          afterKey: "target_after",
          pick: (page) => page.targets,
          onSpacecraft: vi.fn(),
          onStale: vi.fn(async () => {}),
        });
        return () => h("div");
      },
    }),
  );
  cleanups.push(() => wrapper.unmount());
  const loaded = required(results);
  const position = loaded.state.value.scrollKey;
  catalog.value = {
    ...initial,
    query: { ...initial.query, target: "target_two" },
    basis: { ...initial.basis, token: "f".repeat(64) },
  };
  await flushPromises();
  expect(loaded.state.value.scrollKey).toBe(position);
  expect(loaded.state.value.entries).toEqual(initial.targets.entries);
});
