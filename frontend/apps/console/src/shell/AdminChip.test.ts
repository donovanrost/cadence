import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it } from "vite-plus/test";
import { nextTick } from "vue";
import { createMemoryHistory, createRouter } from "vue-router";
import type { Session } from "@/api/session.ts";
import AdminChip from "./AdminChip.vue";
import { seedAdminMode } from "./admin-mode.ts";

const session: Session = {
  user: { id: "u", email: "a@example.com", display_name: null },
  current_organization_id: null,
  platform_admin_eligible: true,
  capabilities: [],
  organizations: [],
  csrf_token: "t",
  socket: { path: "/socket" },
  admin_mode: true,
  admin_mode_expires_at: new Date(Date.now() + 30 * 60_000).toISOString(),
  pending_invitations_count: null,
};
afterEach(() => seedAdminMode({ ...session, admin_mode: false, admin_mode_expires_at: null }));

describe("admin mode chip as a menu button (design-language §6)", () => {
  it("opens on its first item, cycles, and closes back to the chip on Esc", async () => {
    seedAdminMode(session);
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [{ path: "/admin", name: "admin", component: { render: () => null } }],
    });
    const w = mount(AdminChip, { global: { plugins: [router] }, attachTo: document.body });
    const chip = w.get("button[aria-haspopup]");
    expect(chip.attributes("aria-haspopup")).toBe("menu");
    await chip.trigger("click");
    await nextTick();
    expect(document.activeElement?.textContent?.trim()).toBe("Admin area");
    const key = (k: string) =>
      document.activeElement?.dispatchEvent(
        new KeyboardEvent("keydown", { key: k, bubbles: true }),
      );
    key("ArrowDown");
    await nextTick();
    expect(document.activeElement?.textContent?.trim()).toBe("Leave admin mode");
    key("Escape");
    await nextTick();
    expect(w.find('[role="menu"]').exists()).toBe(false);
    expect(document.activeElement).toBe(chip.element);
    w.unmount();
  });
});
