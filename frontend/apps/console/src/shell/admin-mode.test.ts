import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import type { Session } from "@/api/session.ts";
import { enterAdminMode, leaveAdminMode, seedAdminMode, useAdminMode } from "./admin-mode.ts";

const base = {
  user: { id: "u", email: "a@example.com", display_name: null },
  current_organization_id: null,
  platform_admin_eligible: true,
  capabilities: [],
  organizations: [],
  csrf_token: "t",
  socket: { path: "/socket" },
} as const;
const session = (on: boolean, expires: string | null): Session => ({
  ...base,
  capabilities: [],
  organizations: [],
  admin_mode: on,
  admin_mode_expires_at: expires,
  pending_invitations_count: null,
});
const reply = (status: number, body: unknown) =>
  vi.stubGlobal("fetch", () =>
    Promise.resolve(
      new Response(body === null ? null : JSON.stringify(body), {
        status,
        headers: { "content-type": "application/json" },
      }),
    ),
  );

afterEach(() => vi.unstubAllGlobals());

describe("L6 admin mode (Auth.md)", () => {
  it("counts down to the server's expiry and says when it's under 5 minutes", () => {
    seedAdminMode(session(true, "2026-11-13T03:10:00Z"));
    let now = new Date("2026-11-13T02:17:50Z");
    const admin = useAdminMode(() => now);
    expect(admin.active.value).toBe(true);
    expect(admin.remaining.value).toBe("00:52:10");
    expect(admin.ending.value).toBe(false);
    now = new Date("2026-11-13T03:06:00Z");
    expect(useAdminMode(() => now).ending.value).toBe(true);
    now = new Date("2026-11-13T03:10:01Z");
    expect(useAdminMode(() => now).active.value).toBe(false);
  });

  it("enters with the right password, says a wrong one plainly, and reads a 429 as throttled", async () => {
    seedAdminMode(session(false, null));
    const now = () => new Date("2026-11-13T02:00:00Z");
    reply(422, { error: { code: "password_incorrect", message: "x", details: {} } });
    expect(await enterAdminMode("nope")).toMatchObject({ ok: false, reason: "wrong_password" });
    reply(429, {
      error: { code: "too_many_attempts", message: "x", details: { retry_after: 40 } },
    });
    expect(await enterAdminMode("nope")).toMatchObject({ ok: false, reason: "throttled" });
    reply(403, { error: { code: "forbidden", message: "x", details: {} } });
    expect(await enterAdminMode("right")).toMatchObject({ ok: false, reason: "forbidden" });
    reply(200, { data: { expires_at: "2026-11-13T03:00:00Z" } });
    expect(await enterAdminMode("right")).toEqual({ ok: true });
    expect(useAdminMode(now).remaining.value).toBe("01:00:00");
    reply(204, null);
    await leaveAdminMode();
    expect(useAdminMode(now).active.value).toBe(false);
  });
});
