import { mount } from "@vue/test-utils";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { nextTick } from "vue";
import CadenceInfiniteScroll from "./CadenceInfiniteScroll.vue";

const observers: TestObserver[] = [];
class TestObserver implements IntersectionObserver {
  readonly root = null;
  readonly rootMargin = "";
  readonly scrollMargin = "";
  readonly thresholds = [];
  readonly disconnect = vi.fn();
  readonly observe = vi.fn();
  readonly unobserve = vi.fn();
  readonly takeRecords = () => [];
  constructor(
    private callback: IntersectionObserverCallback,
    readonly options?: IntersectionObserverInit,
  ) {
    observers.push(this);
  }
  intersect() {
    const target = document.createElement("div");
    const rect = target.getBoundingClientRect();
    this.callback(
      [
        {
          target,
          isIntersecting: true,
          intersectionRatio: 1,
          time: 0,
          boundingClientRect: rect,
          intersectionRect: rect,
          rootBounds: rect,
        },
      ],
      this,
    );
  }
}
afterEach(() => {
  vi.unstubAllGlobals();
  observers.length = 0;
});
test("uses the pane scroll root, suppresses duplicates and rechecks visibility after a page arrives", async () => {
  vi.stubGlobal("IntersectionObserver", TestObserver);
  const root = document.createElement("div");
  const wrapper = mount(CadenceInfiniteScroll, { props: { root, hasMore: true, loading: false } });
  await nextTick();
  const first = observers[0];
  expect(first?.options?.root).toBe(root);
  first?.intersect();
  first?.intersect();
  expect(wrapper.emitted("loadMore")).toHaveLength(1);
  await wrapper.setProps({ loading: true });
  expect(first?.disconnect).toHaveBeenCalled();
  await wrapper.setProps({ loading: false });
  expect(wrapper.emitted("loadMore")).toHaveLength(1);
  observers[1]?.intersect();
  expect(wrapper.emitted("loadMore")).toHaveLength(2);
  await wrapper.setProps({ hasMore: false });
  expect(observers[1]?.disconnect).toHaveBeenCalled();
  observers[1]?.intersect();
  expect(wrapper.emitted("loadMore")).toHaveLength(2);
  wrapper.unmount();
});
test("pauses for errors, provides an accessible retry and ignores observers after unmount", async () => {
  vi.stubGlobal("IntersectionObserver", TestObserver);
  const wrapper = mount(CadenceInfiniteScroll, {
    props: {
      root: document.createElement("div"),
      hasMore: true,
      loading: false,
      error: "Connection lost",
    },
  });
  await nextTick();
  expect(observers).toHaveLength(0);
  await wrapper.get("button").trigger("click");
  expect(wrapper.emitted("retry")).toHaveLength(1);
  await wrapper.setProps({ error: "" });
  const observer = observers[0];
  wrapper.unmount();
  observer?.intersect();
  expect(wrapper.emitted("loadMore")).toBeUndefined();
  expect(observer?.disconnect).toHaveBeenCalled();
});
