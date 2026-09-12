import { afterEach, expect, test } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import ApplicationShell from "./ApplicationShell.vue";
import { PrimaryNavigation as ShellNavigation } from "../auth-and-navigation";
import { context } from "../auth-and-navigation/shared/context.test-support";
let wrapper;
const render = (variant, overrides = {}) =>
  (wrapper = mount(ApplicationShell, {
    attachTo: document.body,
    props: { variant, context: { ...context, ...overrides } },
    slots: { default: '<section id="page-content">Page content</section>' },
  }));
afterEach(() => {
  wrapper?.unmount();
  document.body.innerHTML = "";
});
test("composes page content inside each frontend shell", () => {
  for (const variant of ["auth", "sidebar", "mission_sidebar", "ops", "user_shell"]) {
    const app = render(variant);
    expect(app.find("#page-content").exists()).toBe(true);
    if (variant !== "auth") expect(app.find("main #page-content").exists()).toBe(true);
    app.unmount();
  }
});
test("organization navigation becomes mission navigation without remounting the sidebar", async () => {
  const app = render("sidebar", { mission: null });
  const sidebar = app.getComponent(ShellNavigation);
  const element = app.get("[data-sidebar-collapsible]").element;
  expect(app.find('a[href="/missions/mission%2F1/spacecraft"]').exists()).toBe(false);
  await app.setProps({
    variant: "mission_sidebar",
    context: { ...context, nav_context: "mission", nav_item: "mission_overview" },
  });
  expect(app.getComponent(ShellNavigation).vm.$.uid).toBe(sidebar.vm.$.uid);
  expect(app.get("[data-sidebar-collapsible]").element).toBe(element);
  expect(app.get('a[href="/missions/mission%2F1"]').attributes("aria-current")).toBe("page");
  expect(app.get('a[href="/missions/mission%2F1/spacecraft"]').text()).toBe("Spacecraft");
  expect(app.get('a[href="/missions/mission%2F1/applications"]').text()).toBe("Applications");
});
