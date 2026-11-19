import { expectAccessible } from "./support/accessibility.ts";
import { jsonData, jsonProblem, missionApi, missionPath, openConsole } from "./support/console.ts";
import { DEMO, storageStateFor } from "./support/env.ts";
import { allow, expect, test } from "./support/fixtures.ts";

// Setup › Spacecraft directory (fe-setup, d53a554e). Data: GET /missions/:id/spacecraft (§S).
const screen = missionPath("setup/spacecraft");
const directoryApi = missionApi("spacecraft");

function directory(page: import("@playwright/test").Page) {
  return page.getByRole("table", { name: "Spacecraft" });
}

test.describe("setup spacecraft directory", () => {
  test("lists every seeded spacecraft with real identity columns", async ({ page }) => {
    await openConsole(page, screen);
    await expect(page.getByRole("heading", { level: 1, name: "Spacecraft" })).toBeVisible();
    await expect(
      page.getByText(`${DEMO.spacecraftCount} spacecraft`, { exact: false }),
    ).toBeVisible();
    await expect(
      page.getByText(`${DEMO.spacecraftCount} of ${DEMO.spacecraftCount}`),
    ).toBeVisible();

    const rows = directory(page).locator("tbody tr");
    await expect(rows).toHaveCount(DEMO.spacecraftCount);
    const first = rows.first();
    await expect(first.getByRole("link", { name: "EARENDIL-001" })).toBeVisible();
    await expect(first).toContainText("Earendil Block 1");
    // No row may claim a SCID it doesn't have (the canvas's "SCID —" finding).
    await expect(directory(page).getByText("SCID —")).toHaveCount(0);

    await expectAccessible(page);
  });

  test("filters by name, SCID prefix and profile, with an honest no-match state", async ({
    page,
  }) => {
    await openConsole(page, screen);
    const filter = page.getByRole("searchbox", { name: "Filter spacecraft" });
    const rows = directory(page).locator("tbody tr");

    await filter.fill("earendil-312");
    await expect(rows).toHaveCount(1);
    await expect(rows.first().getByRole("link")).toHaveText("EARENDIL-312");

    await filter.fill("31");
    // SCID prefix 31, 310–319 and names containing "31".
    await expect(rows.first()).toBeVisible();
    for (const name of await rows.getByRole("link").allInnerTexts()) {
      expect(name).toContain("31");
    }

    await filter.fill("no-such-spacecraft");
    await expect(directory(page)).toHaveCount(0);
    await expect(page.getByText("No spacecraft match")).toBeVisible();
    await expect(page.getByText("0 of 500")).toBeVisible();

    await filter.fill("");
    await expect(rows).toHaveCount(DEMO.spacecraftCount);
  });

  test("keyboard: filter, then open a spacecraft from its Name link", async ({ page }) => {
    await openConsole(page, screen);
    const filter = page.getByRole("searchbox", { name: "Filter spacecraft" });
    await filter.focus();
    await page.keyboard.type("EARENDIL-042");
    await expect(directory(page).locator("tbody tr")).toHaveCount(1);
    await page.keyboard.press("Tab");
    await expect(page.getByRole("link", { name: "EARENDIL-042" })).toBeFocused();
    await page.keyboard.press("Enter");
    await expect(page).toHaveURL(/\/setup\/spacecraft\/[^/]+$/);
  });

  test("empty mission shows the add-spacecraft empty state", async ({ page }) => {
    await page.route(directoryApi, (route) => route.fulfill(jsonData({ spacecraft: [] })));
    await openConsole(page, screen);
    await expect(page.getByText("No spacecraft yet")).toBeVisible();
    await expect(page.getByRole("searchbox", { name: "Filter spacecraft" })).toHaveCount(0);
    await expect(page.getByRole("link", { name: "Add spacecraft" }).last()).toBeVisible();
    await expectAccessible(page);
  });

  test.describe("when the directory read fails", () => {
    test.use({ allowedDiagnostics: allow(/\/spacecraft -> 500/, /status of 500/) });

    test("shows a retryable error, then recovers", async ({ page }) => {
      await page.route(directoryApi, (route) => route.fulfill(jsonProblem(500, "internal_error")));
      await openConsole(page, screen);
      const retry = page.getByRole("button", { name: "Retry" });
      await expect(retry).toBeVisible();
      await expect(directory(page)).toHaveCount(0);

      await page.unroute(directoryApi);
      await retry.click();
      await expect(directory(page).locator("tbody tr")).toHaveCount(DEMO.spacecraftCount);
    });
  });
});

test.describe("setup spacecraft directory, organization member", () => {
  test.use({ storageState: storageStateFor("operator") });

  test("can read the directory", async ({ page }) => {
    await openConsole(page, screen);
    await expect(directory(page).locator("tbody tr")).toHaveCount(DEMO.spacecraftCount);
  });

  test("is not offered Add spacecraft (no manage_mission capability)", async ({ page }) => {
    await openConsole(page, screen);
    await expect(directory(page)).toBeVisible();
    await expect(page.getByRole("link", { name: "Add spacecraft" })).toHaveCount(0);
  });
});
