import { expectAccessible } from "./support/accessibility.ts";
import { jsonData, jsonProblem, missionApi, missionPath, openConsole } from "./support/console.ts";
import { allow, expect, test } from "./support/fixtures.ts";

// Setup › Spacecraft detail, Profiles list, Catalog index (fe-setup).

test.describe("Setup spacecraft detail", () => {
  test("opens from the directory with real identity, readiness and routing", async ({ page }) => {
    await openConsole(page, missionPath("setup/spacecraft"));
    await page.getByRole("link", { name: "EARENDIL-001", exact: true }).click();
    // The heading names the SCID too ("EARENDIL-001 · SCID 1").
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(/^EARENDIL-001\b/);
    await expect(page.getByText("Ready", { exact: true }).first()).toBeVisible();

    await expect(page.getByText("SCID 1", { exact: true })).toBeVisible();
    await expect(page.getByText("Earendil Block 1").first()).toBeVisible();
    // The seed gives every spacecraft a primary and a candidate downlink route, plus an uplink
    // route since the uplink legs (domain 0a08bcbc).
    const rows = page.getByRole("table").locator("tbody tr");
    await expect(rows).toHaveCount(3);
    await expect(rows.filter({ hasText: /downlink/i }).filter({ hasText: /primary/i })).toHaveCount(
      1,
    );
    await expect(rows.filter({ hasText: /TT&C uplink/i })).toHaveCount(1);

    // Decision 1's placeholder ("configuration arrives with change sets") is gone now that change
    // sets exist; the routing rows above are what the detail reads (#624 triage).
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
  test("shows the seeded catalog's current revision and its last import", async ({ page }) => {
    await openConsole(page, missionPath("setup/catalog"));
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    await expect(page.getByText(/revision 1/i).first()).toBeVisible();
    await expect(page.getByText("demo_spacecraft.yaml").first()).toBeVisible();
    await expect(page.getByText(/no catalog yet|not available/i)).toHaveCount(0);
    await expectAccessible(page);
  });

  test("a mission without a catalog says so and offers the import", async ({ page }) => {
    await page.route(missionApi("catalog"), (route) =>
      route.fulfill(jsonData({ databases: [], database: null })),
    );
    await openConsole(page, missionPath("setup/catalog"));
    await expect(page.getByRole("heading", { level: 1, name: "No catalog yet" })).toBeVisible();
  });

  test.describe("on a server without the catalog endpoint", () => {
    test.use({ allowedDiagnostics: allow(/\/catalog -> 404/, /status of 404/) });

    test("says the catalog isn't available rather than showing an empty one", async ({ page }) => {
      await page.route(missionApi("catalog"), (route) =>
        route.fulfill(jsonProblem(404, "not_found")),
      );
      await openConsole(page, missionPath("setup/catalog"));
      await expect(page.getByText("Catalog not available in the console yet")).toBeVisible();
      await expect(page.getByText("No catalog yet")).toHaveCount(0);
    });
  });
});
