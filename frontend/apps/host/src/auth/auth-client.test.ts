import { describe, expect, it, vi } from "vite-plus/test";
import { currentSession, signIn } from "./auth-client";

const session = {
  schema: "cadence.frontend-session.v1",
  actor: { displayName: "Cadence Administrator", email: "admin@example.com" },
  authority: {
    role: "platform_admin",
    adminModeExpiresAt: "2026-08-23T20:00:00.000Z",
  },
  environment: { mode: "development", name: "Local development" },
} as const;

describe("auth client", () => {
  it("treats an unauthorized current-session response as signed out", async () => {
    const fetcher = vi.fn(async () => new Response(null, { status: 204 }));
    await expect(currentSession(fetcher as typeof fetch)).resolves.toBeUndefined();
  });

  it("uses the same-origin session boundary for sign in", async () => {
    const fetcher = vi.fn(async () => Response.json(session, { status: 201 }));
    await expect(
      signIn({ email: "admin@example.com", password: "change-me" }, fetcher as typeof fetch),
    ).resolves.toEqual(session);

    expect(fetcher).toHaveBeenCalledWith(
      "/api/cadence/session",
      expect.objectContaining({ method: "POST", credentials: "same-origin" }),
    );
  });

  it("preserves the session boundary's generic credential error", async () => {
    const fetcher = vi.fn(async () =>
      Response.json(
        {
          schema: "cadence.frontend-session-problem.v1",
          code: "invalid_credentials",
          message: "The supplied email or password was rejected.",
        },
        { status: 401 },
      ),
    );

    await expect(
      signIn({ email: "unknown@example.com", password: "wrong" }, fetcher as typeof fetch),
    ).rejects.toThrow("The supplied email or password was rejected.");
  });
});
