import { expectAccessible } from "./support/accessibility.ts";
import { missionPath, openConsole } from "./support/console.ts";
import { allow, expect, test } from "./support/fixtures.ts";

// Setup › Spacecraft detail, Profiles list, Catalog index (fe-setup).

test.describe("Setup spacecraft detail", () => {
  test("opens from the directory with real identity, readiness and routing", async ({ page }) => {
    await openConsole(page, missionPath("setup/spacecraft"));
    await page.getByRole("link", { name: "EARENDIL-001", exact: true }).click();
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("EARENDIL-001");
    await expect(page.getByText("Ready", { exact: true }).first()).toBeVisible();

    await expect(page.getByText("SCID 1", { exact: true })).toBeVisible();
    await expect(page.getByText("Earendil Block 1").first()).toBeVisible();
    // The seed gives every spacecraft a primary and a backup downlink route.
    await expect(page.getByRole("table").locator("tbody tr")).toHaveCount(2);
    await expect(page.getByRole("cell", { name: /^primary$/i })).toBeVisible();

    // Decision 1: no mission revision numbers until change sets exist.
    await expect(page.getByText(/configuration arrives with change sets/i)).toBeVisible();
    await expectAccessible(page);
  });

  test("Open in Ops goes to the same spacecraft in the console", async ({ page }) => {
    await openConsole(page, missionPath("setup/spacecraft/spacecraft-earendil-001"));
    await page.getByRole("link", { name: /open in ops/i }).click();
    await expect(page).toHaveURL(/\/fleet\/1(?:\/|$)/);
  });
});

test.describe("Setup profiles", () => {
  test("lists the seeded profile", async ({ page }) => {
    await openConsole(page, missionPath("setup/profiles"));
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(/1 profile/i);
    await expect(page.getByRole("link", { name: /Earendil Block 1/ }).first()).toBeVisible();
    await expectAccessible(page);
  });
});

test.describe("Setup catalog", () => {
  test.use({ allowedDiagnostics: allow(/\/catalog -> 404/, /status of 404/) });

  test("says the catalog index isn't available instead of showing an empty catalog", async ({
    page,
  }) => {
    await openConsole(page, missionPath("setup/catalog"));
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(/catalog/i);
    await expect(page.getByText(/not available/i).first()).toBeVisible();
    await expect(page.getByText(/no catalog|0 packets/i)).toHaveCount(0);
    await expectAccessible(page);
  });
});
