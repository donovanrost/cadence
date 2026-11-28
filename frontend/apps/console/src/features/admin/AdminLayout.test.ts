import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it } from "vite-plus/test";
import { createMemoryHistory, createRouter } from "vue-router";
import type { Session } from "@/api/session.ts";
import { seedAdminMode } from "@/shell/admin-mode.ts";
import AdminLayout from "./AdminLayout.vue";

const session: Session = {
  user: { id: "u", email: "a@example.com", display_name: null },
  current_organization_id: null,
  platform_admin_eligible: true,
  capabilities: [],
  organizations: [],
  csrf_token: "t",
  socket: { path: "/socket" },
  admin_mode: false,
  admin_mode_expires_at: null,
  pending_invitations_count: null,
  unread_notices_count: 0,
};
afterEach(() => seedAdminMode(session));

async function mountAt() {
  const router = createRouter({
    history: createMemoryHistory(),
    // AdminLayout is mounted directly; its RouterView renders this stand-in for the routed page.
    routes: [{ path: "/admin/audit", component: { template: "<h1>Audit</h1>" } }],
  });
  await router.push("/admin/audit");
  await router.isReady();
  return mount(AdminLayout, { global: { plugins: [router] } });
}

describe("admin layout's step-up gate (a11y S1)", () => {
  it("renders exactly one h1 while admin mode is off, the routed page not mounted", async () => {
    seedAdminMode(session);
    const w = await mountAt();
    const h1s = w.findAll("h1");
    expect(h1s).toHaveLength(1);
    expect(h1s[0]?.text()).toBe("Admin mode");
    expect(w.text()).not.toContain("Audit");
  });

  it("shows the routed page, with its own h1 only, once admin mode is on", async () => {
    seedAdminMode({
      ...session,
      admin_mode: true,
      admin_mode_expires_at: new Date(Date.now() + 30 * 60_000).toISOString(),
    });
    const w = await mountAt();
    expect(w.findAll("h1").map((h) => h.text())).toEqual(["Audit"]);
  });
});
