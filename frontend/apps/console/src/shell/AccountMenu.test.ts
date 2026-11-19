import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { defineComponent, h, nextTick } from "vue";
import { createMemoryHistory, createRouter } from "vue-router";
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
