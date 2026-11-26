import { request, type Page, type WebSocket } from "@playwright/test";
import { expectAccessible } from "./support/accessibility.ts";
import { missionPath, openConsole } from "./support/console.ts";
import { BASE_URL, DEMO, PERSONAS, storageStateFor } from "./support/env.ts";
import { allow, expect, test } from "./support/fixtures.ts";
import { signInByApi } from "./support/sign-in.ts";

// Shell contract: frontend/apps/console/ARCHITECTURE.md "Building a screen".
test.describe("console shell", () => {
  test("a signed-in operator lands on /console with real org and mission context", async ({
    page,
  }) => {
    await openConsole(page);
    await expect(page).toHaveURL(/\/console(?:[/?#]|$)/);

    const banner = page.getByRole("banner");
    await expect(banner).toBeVisible();
    await expect(banner).toContainText(DEMO.organizationName);
    await expect(banner).toContainText(DEMO.missionName);

    const navigation = page.getByRole("navigation").first();
    await expect(navigation).toBeVisible();
    await expect(navigation).toHaveAccessibleName(/.+/);
    await expect(page.getByRole("main")).toHaveCount(1);
    await expect(page.getByRole("heading", { level: 1 })).toHaveCount(1);

    // The shell's chrome only; each screen's own spec scans its <main>.
    await expectAccessible(page, { exclude: ["main"] });
  });

  test("an unknown deep link reloads into an in-shell Not found screen", async ({ page }) => {
    const response = await openConsole(page, "/console/__qa-unknown-route");
    expect(response?.status(), "Phoenix serves the SPA index for any /console path").toBe(200);
    await expect(page.getByRole("banner")).toBeVisible();
    await expect(page.getByRole("heading", { level: 1 })).toHaveCount(1);
    await expect(page.getByRole("heading", { level: 1 })).toContainText(/not found/i);
    await expectAccessible(page);
  });
});

test.describe("console shell, capability gating (decision 2, qa #4)", () => {
  // People & access is open to members (SetupRail: adminOnly false); these two stay admin-only.
  const orgAdminLinks = ["Provider accounts", "Audit log"];

  test("a member doesn't see organization administration", async ({ browser }) => {
    const context = await browser.newContext({ storageState: storageStateFor("operator") });
    const page = await context.newPage();
    await openConsole(page, missionPath("setup/spacecraft"));
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    for (const name of orgAdminLinks) await expect(page.getByRole("link", { name })).toHaveCount(0);
    await context.close();
  });

  test("an organization admin (not platform admin) does", async ({ browser }) => {
    const context = await browser.newContext({ storageState: storageStateFor("orgAdmin") });
    const page = await context.newPage();
    await openConsole(page, missionPath("setup/spacecraft"));
    for (const name of orgAdminLinks)
      await expect(page.getByRole("link", { name }).first()).toBeVisible();
    await context.close();
  });
});

test.describe("console shell, platform admin without a membership", () => {
  test.use({ storageState: storageStateFor("admin") });

  test("admin mode can open any organization by URL (session.md, qa #15)", async ({ page }) => {
    await openConsole(page, missionPath("now"));
    await expect(page.getByRole("banner")).toContainText(DEMO.organizationName);
  });
});

test.describe("console shell, signed out", () => {
  test.use({
    storageState: { cookies: [], origins: [] },
    // A signed-out console's session read answers 401, which it reads as anonymous.
    allowedDiagnostics: allow(/\/api\/v1\/session/),
  });

  test("redirects to the console sign-in screen", async ({ page }) => {
    // /console → 302 /console/sign-in.
    await page.goto("/console");
    await expect(page).toHaveURL(/\/console\/sign-in(?:[/?#]|$)/);
    await expect(page.getByRole("heading", { level: 1, name: "Sign in" })).toBeVisible();
  });
});

/** The console's live sockets a tab opens (`/socket/websocket`), in order. */
function liveSockets(tab: Page): WebSocket[] {
  const seen: WebSocket[] = [];
  tab.on("websocket", (ws) => {
    if (ws.url().includes("/socket/websocket")) seen.push(ws);
  });
  return seen;
}

// #664: sign-out goes through DELETE /api/v1/session. Its own session (signed in here, through the
// API), so revoking it leaves the shared persona sessions alone.
test.describe("console shell, sign-out", () => {
  test.use({
    storageState: async ({ baseURL }, use, testInfo) => {
      const path = testInfo.outputPath("sign-out-session.json");
      await signInByApi(baseURL ?? BASE_URL, PERSONAS.operator, path);
      await use(path);
    },
    // After the session ends, the other tab's socket reconnects and is refused, and its reads 401.
    allowedDiagnostics: allow(/\/socket\/websocket/, /\/api\/v1\/.* -> 401/, /status of 401/),
  });

  test("ends the session, disconnects every tab's live socket and refuses the old cookie", async ({
    page,
    context,
  }) => {
    const other = await context.newPage();
    const otherSockets = liveSockets(other);
    await openConsole(other, missionPath("now"));
    await expect.poll(() => otherSockets.length).toBeGreaterThan(0);
    await openConsole(page, missionPath("now"));
    const before = await context.storageState();
    // The other tab's socket that's open now; nothing on the client closes it, only the server.
    await expect.poll(() => otherSockets.filter((ws) => !ws.isClosed()).length).toBe(1);
    const open = otherSockets.find((ws) => !ws.isClosed());

    await page.getByRole("button", { name: /account menu for/i }).click();
    await page.getByRole("menuitem", { name: "Sign out" }).click();

    await expect(page).toHaveURL(/\/console\/sign-in(?:[/?#]|$)/);
    // The other tab never navigated: only the server's disconnect closes its socket, at once.
    await expect.poll(() => open?.isClosed(), { timeout: 2_000 }).toBe(true);
    expect(other.url()).toContain(missionPath("now"));
    const old = await request.newContext({ baseURL: BASE_URL, storageState: before });
    expect((await old.get("/api/v1/session")).status()).toBe(401);
    await old.dispose();
  });

  // #876: Account's "Sign out other sessions" disconnects those sessions' live sockets too. It ends
  // EVERY other session of the person, so it runs as `second`, whom no other spec signs in as.
  test.describe("as a person no other spec uses", () => {
    test.use({
      storageState: async ({ baseURL }, use, testInfo) => {
        const path = testInfo.outputPath("second-session.json");
        await signInByApi(baseURL ?? BASE_URL, PERSONAS.second, path);
        await use(path);
      },
    });

    test("signing out other sessions closes their live sockets and keeps this one", async ({
      page,
      browser,
      baseURL,
    }, testInfo) => {
      const elsewhere = testInfo.outputPath("other-session.json");
      await signInByApi(baseURL ?? BASE_URL, PERSONAS.second, elsewhere);
      const otherContext = await browser.newContext({ storageState: elsewhere });
      const other = await otherContext.newPage();
      const otherSockets = liveSockets(other);
      const mySockets = liveSockets(page);
      await openConsole(other, missionPath("now"));
      await expect.poll(() => otherSockets.filter((ws) => !ws.isClosed()).length).toBe(1);
      const theirs = otherSockets.find((ws) => !ws.isClosed());

      await openConsole(page, "/console/account");
      await expect.poll(() => mySockets.filter((ws) => !ws.isClosed()).length).toBe(1);
      const mine = mySockets.find((ws) => !ws.isClosed());
      await page.getByRole("button", { name: "Sign out other sessions" }).click();
      await expect(page.getByText(/Signed out \d+ other sessions?\./)).toBeVisible();

      await expect.poll(() => theirs?.isClosed(), { timeout: 2_000 }).toBe(true);
      expect(other.url()).toContain(missionPath("now"));
      expect((await otherContext.request.get("/api/v1/session")).status()).toBe(401);
      // This session stays signed in, socket and all.
      expect(mine?.isClosed()).toBe(false);
      expect((await page.request.get("/api/v1/session")).status()).toBe(200);
      await otherContext.close();
    });
  });
});
