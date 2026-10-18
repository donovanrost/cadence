import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import { defineComponent, h, ref } from "vue";
import { createPageRegistry, useLazyPage } from "./lazy-pages";

function deferred<T>() {
  let settle: ((value: T) => void) | undefined;
  let fail: ((cause: unknown) => void) | undefined;
  const promise = new Promise<T>((resolve, reject) => {
    settle = resolve;
    fail = reject;
  });
  return {
    promise,
    resolve(value: T) {
      if (!settle) throw Error("Missing resolver");
      settle(value);
    },
    reject(cause: unknown) {
      if (!fail) throw Error("Missing rejecter");
      fail(cause);
    },
  };
}
const entry = (id: string) => ({ id, slot: "ops.page", version: 1, read: () => ({}) });
afterEach(() => vi.useRealTimers());
test("only selected code loads, and a late import cannot replace the newly selected page", async () => {
  const first = deferred<ReturnType<typeof entry>>(),
    second = deferred<ReturnType<typeof entry>>();
  const loadFirst = vi.fn(() => first.promise),
    loadSecond = vi.fn(() => second.promise);
  const registry = createPageRegistry("ops.page", { first: loadFirst, second: loadSecond });
  expect(loadFirst).not.toHaveBeenCalled();
  const id = ref("first"),
    report = vi.fn();
  const wrapper = mount(
    defineComponent({
      setup() {
        const page = useLazyPage(() => id.value, registry, report);
        return () =>
          h(
            "p",
            page.state.value.kind === "ready" ? page.state.value.value.id : page.state.value.kind,
          );
      },
    }),
  );
  expect(wrapper.text()).toBe("loading");
  expect(loadSecond).not.toHaveBeenCalled();
  id.value = "second";
  second.resolve(entry("second"));
  await flushPromises();
  expect(wrapper.text()).toBe("second");
  first.resolve(entry("first"));
  await flushPromises();
  expect(wrapper.text()).toBe("second");
  expect(report).not.toHaveBeenCalled();
  wrapper.unmount();
});
test("timed-out imports can retry and disposal cancels timers and suppresses late failures", async () => {
  vi.useFakeTimers();
  const pending = deferred<ReturnType<typeof entry>>();
  const registry = createPageRegistry("ops.page", { page: () => pending.promise });
  const report = vi.fn();
  const wrapper = mount(
    defineComponent({
      setup() {
        const page = useLazyPage(() => "page", registry, report, 10);
        return () => h("button", { onClick: page.reload }, page.state.value.kind);
      },
    }),
  );
  await vi.advanceTimersByTimeAsync(10);
  expect(wrapper.text()).toBe("failed");
  expect(report).toHaveBeenCalledOnce();
  pending.resolve(entry("page"));
  await flushPromises();
  expect(wrapper.text()).toBe("failed");
  await wrapper.trigger("click");
  expect(wrapper.text()).toBe("ready");
  wrapper.unmount();
  expect(vi.getTimerCount()).toBe(0);

  const late = deferred<ReturnType<typeof entry>>();
  const another = mount(
    defineComponent({
      setup() {
        useLazyPage(() => "late", { peek: () => undefined, load: () => late.promise }, report, 10);
        return () => h("p");
      },
    }),
  );
  another.unmount();
  late.reject(Error("Disposed load"));
  await flushPromises();
  expect(report).toHaveBeenCalledOnce();
  expect(vi.getTimerCount()).toBe(0);
});
test("a mismatched module is never cached and failed imports can be requested again", async () => {
  const loader = vi.fn(async () => entry("foreign"));
  const registry = createPageRegistry("ops.page", { page: loader });
  await expect(registry.load("page")).rejects.toThrow("placement");
  expect(registry.peek("page")).toBeUndefined();
  loader.mockResolvedValueOnce(entry("page"));
  await expect(registry.load("page")).resolves.toHaveProperty("id", "page");
  await expect(registry.load("__proto__")).rejects.toThrow("Unknown");
});
