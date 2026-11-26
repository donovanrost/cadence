import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { defineComponent, h, nextTick } from "vue";
import { createMemoryHistory, createRouter } from "vue-router";
import { setCsrfToken } from "@/api/http.ts";
import type { Session } from "@/api/session.ts";
import AccountMenu from "./AccountMenu.vue";
import { provideSession } from "./session.ts";

const session: Session = {
  user: { id: "u", email: "ana@example.com", display_name: "Ana Reyes" },
  current_organization_id: null,
  platform_admin_eligible: false,
  capabilities: [],
  organizations: [],
  csrf_token: "t",
  socket: { path: "/socket" },
  admin_mode: false,
  admin_mode_expires_at: null,
  pending_invitations_count: null,
};
const Host = defineComponent(() => {
  provideSession(session);
  return () => h(AccountMenu);
});
async function opened() {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: "/account", name: "account", component: { render: () => null } }],
  });
  const w = mount(Host, { global: { plugins: [router] }, attachTo: document.body });
  await w.get("button[aria-haspopup]").trigger("click");
  await nextTick();
  return w;
}

describe("account menu as a menu button (design-language §6)", () => {
  it("is a named menu whose first item takes focus on open", async () => {
    const w = await opened();
    expect(w.get("button[aria-haspopup]").attributes("aria-haspopup")).toBe("menu");
    expect(w.get('[role="menu"]').attributes("aria-label")).toBe("Account menu for Ana Reyes");
    expect(document.activeElement?.textContent?.trim()).toBe("Your account");
    w.unmount();
  });
  it("cycles its items (Your account, Sign out) and closes back to the trigger on Esc", async () => {
    const w = await opened();
    const key = (k: string) =>
      document.activeElement?.dispatchEvent(
        new KeyboardEvent("keydown", { key: k, bubbles: true }),
      );
    key("ArrowDown");
    await nextTick();
    expect(document.activeElement?.textContent?.trim()).toBe("Sign out");
    key("ArrowDown");
    await nextTick();
    expect(document.activeElement?.textContent?.trim()).toBe("Your account");
    key("Escape");
    await nextTick();
    expect(w.find('[role="menu"]').exists()).toBe(false);
    expect(document.activeElement).toBe(w.get("button[aria-haspopup]").element);
    w.unmount();
  });
});

/** #664: Sign out goes through the console API; a failure never looks signed out. */
describe("account menu sign-out", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });
  const problem = (status: number, code: string) =>
    new Response(JSON.stringify({ error: { code, message: "Cadence is unavailable." } }), {
      status,
      headers: { "content-type": "application/json" },
    });
  async function signOutFromMenu() {
    const w = await opened();
    const item = w.findAll('[role="menuitem"]').find((i) => i.text() === "Sign out");
    await item?.trigger("click");
    await flushPromises();
    return w;
  }

  it("sends DELETE /api/v1/session with the CSRF header, then goes to sign-in", async () => {
    setCsrfToken("csrf-from-bootstrap");
    const assign = vi.spyOn(window.location, "assign").mockImplementation(() => undefined);
    const fetch = vi.fn().mockResolvedValue(new Response(null, { status: 204 }));
    vi.stubGlobal("fetch", fetch);
    const w = await signOutFromMenu();
    const [url, init] = fetch.mock.calls[0] as [string, RequestInit];
    expect(url).toBe("/api/v1/session");
    expect(init.method).toBe("DELETE");
    expect(init.headers).toMatchObject({ "x-csrf-token": "csrf-from-bootstrap" });
    expect(assign).toHaveBeenCalledWith("/console/sign-in");
    w.unmount();
  });

  it("treats a 401 as already signed out", async () => {
    const assign = vi.spyOn(window.location, "assign").mockImplementation(() => undefined);
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(problem(401, "unauthenticated")));
    const w = await signOutFromMenu();
    expect(assign).toHaveBeenCalledWith("/console/sign-in");
    w.unmount();
  });

  it("says a failed sign-out, stays signed in, and Dismiss hands focus to the trigger", async () => {
    const assign = vi.spyOn(window.location, "assign").mockImplementation(() => undefined);
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(problem(503, "unavailable")));
    const w = await signOutFromMenu();
    expect(assign).not.toHaveBeenCalled();
    const failure = () =>
      w.findAll('[role="alert"]').find((a) => a.text().includes("Couldn't sign out."));
    const alert = failure();
    expect(alert?.text()).toContain("Cadence is unavailable.");
    const dismiss = alert?.findAll("button").find((b) => b.text() === "Dismiss");
    await dismiss?.trigger("click");
    expect(failure()).toBeUndefined();
    expect(document.activeElement).toBe(w.get("button[aria-haspopup]").element);
    w.unmount();
  });
});
