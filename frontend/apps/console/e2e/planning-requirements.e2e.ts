import { expectAccessible } from "./support/accessibility.ts";
import { missionPath, openConsole } from "./support/console.ts";
import { DEMO, storageStateFor } from "./support/env.ts";
import { allow, expect, test } from "./support/fixtures.ts";

// CP1 · Contact planning requirements + template detail (fe-setup). Seed: 10 recurring downlink
// templates (one per EARENDIL-001…010), 5-min contacts every 6 h (dev/seed/planning.exs).
const screen = missionPath("setup/contact-planning");
const quiet = allow(/\/contact-planning -> 404/, /status of 404/);

test.describe("Contact planning requirements, organization admin", () => {
  test.use({ allowedDiagnostics: quiet });

  test("states coverage honestly and lists the seeded templates", async ({ page }) => {
    await openConsole(page, screen);
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(
      new RegExp(`${DEMO.spacecraftCount - 10} spacecraft have no contact rule`, "i"),
    );
    const table = page.getByRole("table");
    await expect(table.locator("tbody tr")).toHaveCount(10);
    await expect(table.locator("tbody tr").first()).toContainText(/downlink ≥ 5 min/);
    await expectAccessible(page);
  });

  test("a template shows its rule, scope and version history", async ({ page }) => {
    await openConsole(page, screen);
    await page
      .getByRole("table")
      .getByRole("link", { name: /EARENDIL-001/ })
      .first()
      .click();
    await expect(page).toHaveURL(/\/contact-planning\/templates\/[^/]+$/);
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(/EARENDIL-001/i);
    await expect(page.getByText(/every 6h 00m/).first()).toBeVisible();
    await expect(
      page.getByRole("table", { name: /template versions/i }).locator("tbody tr"),
    ).not.toHaveCount(0);
    await expectAccessible(page);
  });

  test("New template opens a form driven by the server's schema", async ({ page }) => {
    await openConsole(page, screen);
    await page
      .getByRole("link", { name: /new template/i })
      .first()
      .click();
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(/new template/i);
    await expect(page.getByRole("combobox", { name: /profile/i }).first()).toBeVisible({
      timeout: 30_000,
    });
    await expectAccessible(page);
  });
});

test.describe("Contact planning requirements, organization member", () => {
  test.use({ storageState: storageStateFor("operator"), allowedDiagnostics: quiet });

  test("can read but isn't offered New template", async ({ page }) => {
    await openConsole(page, screen);
    await expect(page.getByRole("table").locator("tbody tr")).toHaveCount(10);
    await expect(page.getByRole("link", { name: /new template/i })).toHaveCount(0);
  });
});
