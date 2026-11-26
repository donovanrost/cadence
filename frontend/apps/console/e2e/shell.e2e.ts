import { expectAccessible } from "./support/accessibility.ts";
import { missionPath, openConsole } from "./support/console.ts";
import { DEMO, storageStateFor } from "./support/env.ts";
import { allow, expect, test } from "./support/fixtures.ts";

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
