import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, it, vi } from "vite-plus/test";
import App from "./App.vue";
import { currentSession, signIn, signOut } from "./auth/auth-client";

vi.mock("./auth/auth-client", () => ({
  currentSession: vi.fn(),
  signIn: vi.fn(),
  signOut: vi.fn(),
}));

const session = {
  schema: "cadence.frontend-session.v1",
  actor: { displayName: "Cadence Administrator", email: "admin@example.com" },
  authority: {
    role: "platform_admin",
    adminModeExpiresAt: "2026-08-23T20:00:00.000Z",
  },
  environment: { mode: "development", name: "Local development" },
} as const;

beforeEach(() => {
  window.history.replaceState({}, "", "/");
  vi.mocked(currentSession).mockReset();
  vi.mocked(signIn).mockReset();
  vi.mocked(signOut).mockReset();
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("Vue frontend entry journey", () => {
  it("redirects an unauthenticated entry to sign in, then lands the admin at overview", async () => {
    vi.mocked(currentSession).mockResolvedValue(undefined);
    vi.mocked(signIn).mockResolvedValue(session);
    const wrapper = mount(App);
    await flushPromises();

    expect(window.location.pathname).toBe("/sign-in");
    expect(wrapper.find("#sign-in-form").exists()).toBe(true);

    await wrapper.get("#admin-email").setValue("admin@example.com");
    await wrapper.get("#admin-password").setValue("change-me");
    await wrapper.get("#sign-in-form").trigger("submit");
    await flushPromises();

    expect(window.location.pathname).toBe("/admin");
    expect(wrapper.find("#admin-overview").exists()).toBe(true);
    wrapper.unmount();
  });

  it("restores a protected admin route when a session is active", async () => {
    window.history.replaceState({}, "", "/admin/organizations");
    vi.mocked(currentSession).mockResolvedValue(session);
    const wrapper = mount(App);
    await flushPromises();

    expect(wrapper.find("#organizations-view").exists()).toBe(true);
    expect(wrapper.get("#admin-nav-02").attributes("aria-current")).toBe("page");
    wrapper.unmount();
  });
});
