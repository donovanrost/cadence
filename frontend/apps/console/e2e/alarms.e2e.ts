import { expectAccessible } from "./support/accessibility.ts";
import { missionPath, openConsole } from "./support/console.ts";
import { routeEpisodeList, type EpisodeSeed } from "./support/episodes.ts";
import { expect, test } from "./support/fixtures.ts";
import { expectNameFallback } from "./support/outcomes.ts";

// Ops › Alarms on alarm episodes (fe-ops 566f6998). Tabs live in ?tab=; rows open Investigate.
const screen = missionPath("alarms");
const seeds: EpisodeSeed[] = [
  { scid: 1, severity: "critical", status: "new", point: "EPS.sa1_current" },
  { scid: 2, severity: "caution", status: "acknowledged", point: "EPS.sa2_current" },
  { scid: 3, severity: "critical", status: "cleared", point: "EPS.sa1_current" },
];

test.describe("Alarms (episodes)", () => {
  test.beforeEach(async ({ page }) => {
    await routeEpisodeList(page, seeds);
  });

  test("Active lists unacknowledged episodes with severity in words", async ({ page }) => {
    await openConsole(page, screen);
    const table = page.getByRole("table");
    await expect(table.getByRole("link", { name: /EARENDIL-001/ })).toBeVisible();
    // Acknowledged and cleared episodes live on their own tabs.
    await expect(table.getByRole("link", { name: /EARENDIL-002/ })).toHaveCount(0);
    await expect(table.getByRole("link", { name: /EARENDIL-003/ })).toHaveCount(0);
    await expect(table).toContainText(/critical/i);
    await expectAccessible(page);
  });

  test("tabs are links that keep the state in the URL", async ({ page }) => {
    await openConsole(page, screen);
    const tabs = page.getByRole("navigation", { name: "Alarm status" });
    await tabs.getByRole("link", { name: /acknowledged/i }).click();
    await expect(page).toHaveURL(/[?&]tab=acknowledged/);
    await expect(page.getByRole("table").getByRole("link", { name: /EARENDIL-002/ })).toBeVisible();
    await expect(page.getByRole("table").getByRole("link", { name: /EARENDIL-001/ })).toHaveCount(
      0,
    );

    await tabs.getByRole("link", { name: /cleared/i }).click();
    await expect(page).toHaveURL(/[?&]tab=cleared/);
    await expect(page.getByRole("table").getByRole("link", { name: /EARENDIL-003/ })).toBeVisible();

    await page.reload();
    await expect(page.getByRole("table").getByRole("link", { name: /EARENDIL-003/ })).toBeVisible();
  });

  test("a row opens Investigate on that spacecraft and point", async ({ page }) => {
    await openConsole(page, screen);
    await page
      .getByRole("table")
      .getByRole("link", { name: /EARENDIL-001/ })
      .first()
      .click();
    await expect(page).toHaveURL(/\/fleet\/1\/investigate\?point=EPS\.sa1_current/);
  });
});

test("with no active episodes the list says so", async ({ page }) => {
  await routeEpisodeList(page, []);
  await openConsole(page, screen);
  await expect(page.getByRole("table")).toHaveCount(0);
  await expect(page.getByRole("main")).toContainText(/no (?:active )?alarms|nothing/i);
});

// #646 (U25): a spacecraft whose name Cadence can't read reads as Unknown spacecraft, never its id.
test("a nameless spacecraft reads as Unknown spacecraft, never its id", async ({ page }) => {
  await routeEpisodeList(page, [
    { scid: 9, severity: "critical", status: "new", point: "EPS.sa1_current", nameless: true },
  ]);
  await openConsole(page, screen);
  await expect(page.getByRole("table")).toBeVisible();
  await expectNameFallback(page, "spacecraft-earendil-009");
});
