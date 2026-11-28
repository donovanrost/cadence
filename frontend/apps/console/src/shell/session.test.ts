import { organizationId as orgIdReader } from "@/api/index.ts";
import { describe, expect, it } from "vite-plus/test";
import type { Session, SessionOrganization } from "@/api/session.ts";
import { canAdministerOrganization } from "./session.ts";

const org = (id: string, capabilities: string[]): SessionOrganization => ({
  id: orgIdReader(id),
  slug: id,
  name: id,
  role: "member",
  capabilities,
  missions: [],
});

const session = (current: readonly string[]): Session => ({
  user: { id: "u", email: "u@example.com", display_name: null },
  current_organization_id: orgIdReader("a"),
  admin_mode: false,
  platform_admin_eligible: false,
  admin_mode_expires_at: null,
  pending_invitations_count: null,
  capabilities: current,
  organizations: [],
  csrf_token: "t",
  socket: { path: "/socket" },
});

describe("canAdministerOrganization", () => {
  it("uses the URL organization's own capabilities, not the session's current org", () => {
    const s = session(["organization_admin"]);
    expect(canAdministerOrganization(s, org("b", []))).toBe(false);
    expect(canAdministerOrganization(session([]), org("b", ["organization_admin"]))).toBe(true);
  });

  it("accepts platform_admin", () => {
    expect(canAdministerOrganization(session([]), org("b", ["platform_admin"]))).toBe(true);
  });
});
