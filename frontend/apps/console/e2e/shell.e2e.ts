import { expectAccessible } from "./support/accessibility.ts";
import { openConsole } from "./support/console.ts";
import { DEMO } from "./support/env.ts";
import { expect, test } from "./support/fixtures.ts";

// Shell contract: docs/apogee/ARCHITECTURE.md "Shell contract", docs/apogee/qa/e2e.md.
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

    await expectAccessible(page);
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

test.describe("console shell, signed out", () => {
  test.use({
    storageState: { cookies: [], origins: [] },
    // The LiveView /sign-in page has no favicon (outside the console); see qa issues #2.
    allowedDiagnostics: [/\/favicon\.ico/],
  });

  test("redirects to the Phoenix sign-in page", async ({ page }) => {
    await page.goto("/console");
    await expect(page).toHaveURL(/\/sign-in(?:[/?#]|$)/);
  });
});
