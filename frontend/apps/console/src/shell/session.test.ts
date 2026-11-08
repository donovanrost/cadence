import { describe, expect, it } from "vite-plus/test";
import type { Session, SessionOrganization } from "@/api/session.ts";
import { canAdministerOrganization } from "./session.ts";

const org = (id: string, role: string | null): SessionOrganization => ({
  id,
  slug: id,
  name: id,
  role,
  missions: [],
});

const session = (capabilities: string[], current: string | null): Session => ({
  user: { id: "u", email: "u@example.com", display_name: null },
  current_organization_id: current,
  admin_mode: false,
  platform_admin_eligible: false,
  capabilities,
  organizations: [org("a", "organization_admin"), org("b", "member")],
  csrf_token: "t",
  socket: { path: "/socket/console" },
});

describe("canAdministerOrganization", () => {
  it("uses session capabilities for the current organization", () => {
    expect(canAdministerOrganization(session([], "a"), org("a", "organization_admin"))).toBe(false);
    expect(
      canAdministerOrganization(session(["organization_admin"], "a"), org("a", "member")),
    ).toBe(true);
  });

  it("derives from the membership role for another organization", () => {
    const s = session(["organization_admin"], "a");
    expect(canAdministerOrganization(s, org("b", "member"))).toBe(false);
    expect(canAdministerOrganization(s, org("c", "organization_admin"))).toBe(true);
  });

  it("lets a platform admin in admin mode administer any organization", () => {
    expect(canAdministerOrganization(session(["platform_admin"], "a"), org("b", null))).toBe(true);
  });
});
