import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import AdminNavbar from "./AdminNavbar.vue";

const session = {
  schema: "cadence.frontend-session.v1",
  actor: { displayName: "Cadence Administrator", email: "admin@example.com" },
  authority: {
    role: "platform_admin",
    adminModeExpiresAt: "2026-08-23T20:00:00.000Z",
  },
  environment: { mode: "development", name: "Local development" },
} as const;

describe("AdminNavbar", () => {
  it("shows the signed-in administrator without page-level navigation copy", () => {
    const wrapper = mount(AdminNavbar, {
      props: { session },
    });

    expect(wrapper.text()).toContain("Cadence Administrator");
    expect(wrapper.find(".admin-navbar__location").exists()).toBe(false);
    expect(wrapper.text()).not.toContain("Administration / Organizations");
    expect(wrapper.text()).not.toContain("POC PREVIEW");
    expect(wrapper.text()).not.toContain("ENVIRONMENT");
    expect(wrapper.text()).not.toContain("AUTHORITY");

    wrapper.unmount();
  });

  it("reveals sign out from the account menu and owns navigation events", async () => {
    const wrapper = mount(AdminNavbar, {
      props: { session },
    });

    expect(wrapper.find("#admin-sign-out").exists()).toBe(false);

    await wrapper.get("#admin-home").trigger("click");
    await wrapper.get("#admin-account-menu-trigger").trigger("click");

    expect(wrapper.get("#admin-account-menu-trigger").attributes("aria-expanded")).toBe("true");
    expect(wrapper.get("#admin-account-menu").text()).toContain("admin@example.com");

    await wrapper.get("#admin-sign-out").trigger("click");

    expect(wrapper.emitted("navigate")).toEqual([["/admin"]]);
    expect(wrapper.emitted("signOut")).toEqual([[]]);
    expect(wrapper.find("#admin-account-menu").exists()).toBe(false);

    wrapper.unmount();
  });

  it("closes an open account menu with Escape", async () => {
    const wrapper = mount(AdminNavbar, {
      attachTo: document.body,
      props: { session },
    });

    await wrapper.get("#admin-account-menu-trigger").trigger("click");
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    await wrapper.vm.$nextTick();

    expect(wrapper.find("#admin-account-menu").exists()).toBe(false);
    expect(document.activeElement).toBe(wrapper.get("#admin-account-menu-trigger").element);

    wrapper.unmount();
  });
});
