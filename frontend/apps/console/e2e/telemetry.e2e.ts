import { expectAccessible } from "./support/accessibility.ts";
import { jsonProblem, missionApi, missionPath, openConsole } from "./support/console.ts";
import { allow, expect, test } from "./support/fixtures.ts";
import { routeHistory } from "./support/history.ts";

// Telemetry explore (fe-ops, 917f35a8). History is a deterministic fixture: the real QuestDB
// samples (2026-11-08) age out of every relative window.
const explore = (query = "") => missionPath(`telemetry${query}`);
const selection = "?sc=1,2&p=EPS.sa1_current";

test.describe("Telemetry explore", () => {
  test("the URL selection plots history and lists the latest values with units", async ({
    page,
  }) => {
    await routeHistory(page);
    await openConsole(page, explore(selection));
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(/explore/i);
    for (const name of ["Remove EARENDIL-001", "Remove EARENDIL-002", "Remove EPS.sa1_current"])
      await expect(page.getByRole("button", { name })).toBeVisible();

    // The plot carries a text equivalent naming its series.
    await expect(page.getByRole("img", { name: /2 series over/i })).toBeVisible();
    const values = page.getByRole("table");
    await expect(values.getByRole("row").filter({ hasText: "EARENDIL-001" })).toContainText(/\d A/);
    await expect(values.getByRole("row").filter({ hasText: "EARENDIL-002" })).toContainText(/\d A/);
    await expectAccessible(page);
  });

  test("removing a chip drops that series and updates the URL", async ({ page }) => {
    await openConsole(page, explore(selection));
    await page.getByRole("button", { name: "Remove EARENDIL-002" }).click();
    await expect(page).toHaveURL(/sc=1(?:&|$)/);
    await expect(page.getByRole("img", { name: /1 series over/i })).toBeVisible();
  });

  test("adding a spacecraft from the picker adds a series", async ({ page }) => {
    await openConsole(page, explore(selection));
    await page
      .getByRole("combobox", { name: "Add spacecraft" })
      .selectOption({ label: "EARENDIL-003" });
    await expect(page.getByRole("button", { name: "Remove EARENDIL-003" })).toBeVisible();
    await expect(page).toHaveURL(/sc=1,2,3|sc=[^&]*3/);
  });

  test("with nothing selected it says how to start", async ({ page }) => {
    await openConsole(page, explore());
    await expect(page.getByText("Pick a point to plot")).toBeVisible();
    await expectAccessible(page);
  });

  test.describe("history store down", () => {
    test.use({ allowedDiagnostics: allow(/\/history\?.* -> 503/, /status of 503/) });

    test("the plot reports the failure instead of an empty chart", async ({ page }) => {
      await page.route(`${missionApi("telemetry/points/*/history")}**`, (route) =>
        route.fulfill(jsonProblem(503, "history_unavailable")),
      );
      await openConsole(page, explore(selection));
      await expect(page.getByText("History not available")).toBeVisible();
      await expect(page.getByRole("img", { name: /series over/i })).toHaveCount(0);
    });
  });
});
