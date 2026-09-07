import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import { createApp, defineComponent, h, inject, ref, type App } from "vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import { pageChromeKey, type PageChrome } from "@cadence/ui/page-chrome";
import HostPage from "./HostPage.vue";

const cleanups: (() => void)[] = [];
afterEach(() => {
  cleanups.reverse().forEach((cleanup) => cleanup());
  cleanups.length = 0;
  document.body.innerHTML = "";
});
function host() {
  let chrome!: PageChrome;
  const Capture = defineComponent({
    setup() {
      chrome = inject(pageChromeKey)!;
      return () => h("div", { id: "remote-root" });
    },
  });
  const wrapper = mount(HostPage, {
    attachTo: document.body,
    props: {
      title: "Spacecraft",
      breadcrumbs: [{ label: "Mission", href: "/missions/one" }, { label: "Spacecraft" }],
    },
    slots: { default: () => h(Capture) },
  });
  cleanups.push(() => wrapper.unmount());
  return { wrapper, chrome };
}
function remote(app: App, chrome: PageChrome) {
  app.provide(pageChromeKey, chrome);
  app.mount(document.querySelector("#remote-root")!);
  cleanups.push(() => app.unmount());
}
describe("host page composition", () => {
  it("renders one heading and semantic breadcrumbs before the remote arrives", () => {
    const { wrapper } = host();
    expect(wrapper.findAll("h1")).toHaveLength(1);
    expect(wrapper.get("h1").text()).toBe("Spacecraft");
    expect(wrapper.get('nav[aria-label="Breadcrumb"] a').attributes("href")).toBe("/missions/one");
    expect(wrapper.get('[aria-current="page"]').text()).toBe("Spacecraft");
  });
  it("composes a separately mounted remote's reactive title and actions outside its root", async () => {
    const { wrapper, chrome } = host();
    const title = ref("Voyager");
    const busy = ref(false);
    const save = vi.fn(() => {
      busy.value = true;
    });
    remote(
      createApp(
        defineComponent({
          setup() {
            return () =>
              h("section", [
                h(
                  CadencePageHeading,
                  { breadcrumbs: [{ label: "Fleet", href: "/fleet" }, { label: title.value }] },
                  {
                    title: () => title.value,
                    actions: () =>
                      h(
                        "button",
                        { id: "save-page", disabled: busy.value, onClick: save },
                        busy.value ? "Saving…" : "Save",
                      ),
                  },
                ),
                h("p", "Domain content"),
              ]);
          },
        }),
      ),
      chrome,
    );
    await flushPromises();
    expect(wrapper.findAll("h1")).toHaveLength(1);
    expect(wrapper.get("h1").text()).toBe("Voyager");
    expect(wrapper.find("#remote-root h1").exists()).toBe(false);
    expect(wrapper.find("#host-page-heading #save-page").exists()).toBe(true);
    await wrapper.get("#save-page").trigger("click");
    expect(save).toHaveBeenCalledTimes(1);
    expect(wrapper.get("#save-page").attributes("disabled")).toBeDefined();
    title.value = "Voyager II";
    await flushPromises();
    expect(wrapper.get("h1").text()).toBe("Voyager II");
    expect(wrapper.get('[aria-current="page"]').text()).toBe("Voyager II");
  });
  it("releases remote content on failure and rejects late writes after the routed page closes", async () => {
    const { wrapper, chrome } = host();
    const app = createApp({
      render: () => h(CadencePageHeading, {}, { title: () => "Remote title" }),
    });
    app.provide(pageChromeKey, chrome).mount(document.querySelector("#remote-root")!);
    await flushPromises();
    app.unmount();
    await flushPromises();
    expect(wrapper.get("h1").text()).toBe("Spacecraft");
    expect(wrapper.find("#host-page-heading button").exists()).toBe(false);
    const owner = Symbol();
    chrome.publish(owner, { regions: ["title"] });
    wrapper.unmount();
    cleanups.pop();
    chrome.publish(Symbol(), { regions: ["actions"], breadcrumbs: [{ label: "Stale" }] });
    chrome.release(owner);
    expect(document.querySelector("#host-page-heading")).toBeNull();
  });
  it("keeps host context when the remote has no breadcrumbs", async () => {
    const { wrapper, chrome } = host();
    remote(
      createApp({
        render: () => h(CadencePageHeading, { breadcrumbs: [] }, { title: () => "Fleet" }),
      }),
      chrome,
    );
    await flushPromises();
    expect(wrapper.get("h1").text()).toBe("Fleet");
    expect(wrapper.get('nav[aria-label="Breadcrumb"] a').attributes("href")).toBe("/missions/one");
    expect(wrapper.get('[aria-current="page"]').text()).toBe("Spacecraft");
  });
  it("uses the same page components when no host is provided", () => {
    const wrapper = mount(CadencePageHeading, {
      slots: {
        title: "Standalone page",
        description: "A consistent preview",
        actions: '<button id="preview-action">Create</button>',
      },
    });
    cleanups.push(() => wrapper.unmount());
    expect(wrapper.get("h1.cd-page-title").text()).toBe("Standalone page");
    expect(wrapper.get(".cd-page-description").text()).toBe("A consistent preview");
    expect(wrapper.find(".cd-page-actions #preview-action").exists()).toBe(true);
  });
});
