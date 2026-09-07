import { afterEach, expect, test } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import ApplicationShell from "./ApplicationShell.vue";
import ShellNavigation from "./ShellNavigation.vue";
import { navigation, opsNavigation } from "./shell-navigation";
import { contextSections } from "./shell-context";
const context = {
  user: { user_id: "user-1", display_name: "Operator", email: "operator@example.test" },
  organization: { organization_id: "org-1", display_name: "Flight Operations" },
  organizations: [
    { organization_id: "org-1", display_name: "Flight Operations" },
    { organization_id: "org-2", display_name: "Engineering" },
  ],
  capabilities: [],
  platform_admin: false,
  admin_mode: false,
  csrf_token: "test-csrf",
  nav_context: "organization",
  nav_item: "missions",
  notifications: [],
  unread_count: 0,
  mission: { mission_id: "mission/1", display_name: "Lunar", slug: "lunar" },
  ops_nav_item: "commands",
  dashboard_navigation: { starred: [], recent: [] },
  dock_surfaces: [],
};
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
test("account switching and sign-out retain native methods and CSRF across updates", async () => {
  const app = render("user_shell");
  await app.get("#account-user-user").trigger("click");
  const form = app.get("#account-user-switch-org-2");
  expect(form.attributes("action")).toBe("/session/organization");
  expect(form.attributes("method")).toBe("post");
  expect(form.get('[name="_method"]').element.value).toBe("put");
  expect(form.get('[name="organization_id"]').element.value).toBe("org-2");
  expect(form.get('[name="_csrf_token"]').element.value).toBe("test-csrf");
  await app.setProps({ context: { ...context, csrf_token: "refreshed-csrf" } });
  expect(app.get("#account-user-switch-org-2").element).toBe(form.element);
  expect(form.get('[name="_csrf_token"]').element.value).toBe("refreshed-csrf");
  expect(app.get('#account-user-sign-out [name="_method"]').element.value).toBe("delete");
});
test("capabilities determine available navigation and active links", () => {
  expect(navigation(context, false).map((item) => item.key)).toEqual([
    "organization_home",
    "missions",
  ]);
  const admin = { ...context, capabilities: ["organization_admin"] };
  expect(navigation(admin, false).some((item) => item.key === "provider_accounts")).toBe(true);
  expect(
    opsNavigation(admin)
      .groups.find((group) => group.key === "act")
      .items.map((item) => item.key),
  ).toEqual(["commands", "activations"]);
  const nav = opsNavigation({
    ...admin,
    ops_context: { pinned_focus: { kind: "command", id: "cmd/a?b" } },
  });
  expect(nav.groups[1].items[0].href).toBe(
    "/missions/mission%2F1/ops/commands?focus_command_id=cmd%2Fa%3Fb",
  );
  expect(nav.groups[1].items[0].active).toBe(true);
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
test("mission sections toggle locally and update their seed when the active route changes", async () => {
  wrapper = mount(ShellNavigation, {
    attachTo: document.body,
    props: { mission: true, context: { ...context, nav_item: "mission_overview" } },
  });
  const trigger = wrapper.get('[aria-controls="mission-sidebar-comms-content"]');
  expect(trigger.attributes("aria-expanded")).toBe("false");
  await trigger.trigger("click");
  expect(trigger.attributes("aria-expanded")).toBe("true");
  await wrapper.setProps({ context: { ...context, nav_item: "comms_transports" } });
  expect(
    wrapper.get('a[href="/missions/mission%2F1/comms/transports"]').attributes("aria-current"),
  ).toBe("page");
});
test("operational context preserves unavailable data, severity and command focus", () => {
  const sections = contextSections({
    ...context,
    ops_context: {
      pinned_focus: { kind: "command", id: "cmd-1" },
      modules: [
        {
          key: "fleet_health",
          status: null,
          count: null,
          freshness: "unavailable",
          observed_at: "2026-09-05T12:00:00Z",
          data: null,
        },
        {
          key: "alarms",
          status: "critical",
          count: 2,
          freshness: "current",
          observed_at: "2026-09-05T12:00:00Z",
          data: { active_count: 2, critical_count: 2 },
        },
      ],
    },
  });
  expect(sections[0].content.available).toBe(false);
  expect(sections[0].observed_at_label).toBe("12:00:00 UTC");
  expect(sections[1].content.badges[0]).toMatchObject({ count: 2, label: "Critical" });
  expect(sections[1].destination).toBe("/missions/mission%2F1/ops/alarms?focus_command_id=cmd-1");
});
