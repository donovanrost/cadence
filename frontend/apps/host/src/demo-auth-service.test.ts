import { describe, expect, it } from "vite-plus/test";
import { DemoAuthService, type DemoAdminCredentials } from "../../../tools/demo-auth-service";

const credentials: DemoAdminCredentials = {
  displayName: "Cadence Administrator",
  email: "admin@example.com",
  password: "change-me",
  ttlSeconds: 3_600,
};

describe("development administrator session boundary", () => {
  it("issues and resolves an HTTP-only platform administrator session", () => {
    const service = new DemoAuthService("development", credentials);
    const created = service.handle({
      method: "POST",
      url: "/api/cadence/session",
      body: { email: "ADMIN@example.com", password: "change-me" },
    });
    const setCookie = created?.headers?.["set-cookie"];

    expect(created).toMatchObject({
      status: 201,
      body: {
        schema: "cadence.frontend-session.v1",
        actor: { email: "admin@example.com" },
        authority: { role: "platform_admin" },
      },
    });
    expect(setCookie).toContain("HttpOnly");
    expect(setCookie).toContain("SameSite=Lax");

    const cookie = setCookie?.split(";", 1)[0];
    const current = service.handle({
      method: "GET",
      url: "/api/cadence/session",
      headers: { cookie },
    });
    expect(current?.status).toBe(200);
  });

  it("does not distinguish an unknown identity from an invalid password", () => {
    const service = new DemoAuthService("development", credentials);
    const unknownIdentity = service.handle({
      method: "POST",
      url: "/api/cadence/session",
      body: { email: "unknown@example.com", password: "change-me" },
    });
    const wrongPassword = service.handle({
      method: "POST",
      url: "/api/cadence/session",
      body: { email: "admin@example.com", password: "wrong" },
    });

    expect(unknownIdentity).toMatchObject({ status: 401, body: wrongPassword?.body });
  });

  it("revokes the current cookie on sign out", () => {
    const service = new DemoAuthService("development", credentials);
    const created = service.handle({
      method: "POST",
      url: "/api/cadence/session",
      body: { email: "admin@example.com", password: "change-me" },
    });
    const cookie = created?.headers?.["set-cookie"]?.split(";", 1)[0];

    const signedOut = service.handle({
      method: "DELETE",
      url: "/api/cadence/session",
      headers: { cookie },
    });
    const current = service.handle({
      method: "GET",
      url: "/api/cadence/session",
      headers: { cookie },
    });

    expect(signedOut?.headers?.["set-cookie"]).toContain("Max-Age=0");
    expect(current?.status).toBe(204);
  });
});
