import { expectAccessible } from "./support/accessibility.ts";
import { discardQaChanges, hasForeignStagedChanges } from "./support/config.ts";
import { jsonProblem, missionApi, missionPath, openConsole } from "./support/console.ts";
import { storageStateFor } from "./support/env.ts";
import { allow, expect, test } from "./support/fixtures.ts";
import { expectSaid, WORDS } from "./support/outcomes.ts";

// Setup › Ground stations edit/add through change sets (fe-setup b63311c7). Edits are staged, never
// applied; values carry MARKER so cleanup discards only QA's changes.
const MARKER = "QA-E2E";
const screen = missionPath("setup/stations");

test.describe.configure({ mode: "serial" });

test.describe("Ground stations (organization admin)", () => {
  test.beforeEach(async ({ request }) => {
    test.skip(await hasForeignStagedChanges(request, MARKER), "someone else has changes staged");
  });
  test.afterEach(async ({ request }) => {
    await discardQaChanges(request, MARKER);
  });

  test("lists the seeded stations", async ({ page }) => {
    await openConsole(page, screen);
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    await expect(page.getByRole("table").locator("tbody tr")).toHaveCount(10);
    await expectAccessible(page);
  });

  test("editing a station stages a change; nothing is live until applied", async ({ page }) => {
    await openConsole(page, screen);
    const first = page.getByRole("table").locator("tbody tr").first().getByRole("link").first();
    const name = (await first.innerText()).trim();
    await first.click();
    const field = page.getByRole("textbox", { name: "Name", exact: true });
    await expect(field).toHaveValue(name);
    await expect(page.getByText("Nothing is live until the change set is applied.")).toBeVisible();
    await expectAccessible(page);

    await field.fill(`${name} ${MARKER}`);
    await page.getByRole("button", { name: "Stage change" }).click();
    await expect(page).toHaveURL(/\/setup\/stations$/);
    await expect(page.getByRole("banner")).toContainText(/1 staged/i);
    // Still the old name in the live list.
    await expect(page.getByRole("table")).toContainText(name);
    await expect(page.getByRole("table")).not.toContainText(MARKER);

    await openConsole(page, missionPath("setup/changes"));
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    await expect(
      page.getByText(new RegExp(`${escaped} · display_name → .*${MARKER}`)),
    ).toBeVisible();
  });

  test.describe("when the server fails while staging", () => {
    test.use({ allowedDiagnostics: allow(/\/stage -> 500/, /status of 500/) });

    // #644 (U20, B6): a 5xx may have committed, so the editor says it's unclear, as an alert, and
    // never that it staged. The POST is stubbed, so nothing reaches the server.
    test("says it's unclear whether anything was staged, never that it was", async ({ page }) => {
      // The station editor stages through the change sets' route (changes/actions.ts stageChange).
      await page.route(missionApi("config/stage"), (route) =>
        route.request().method() === "POST"
          ? route.fulfill(jsonProblem(500, "internal_error"))
          : route.continue(),
      );
      await openConsole(page, screen);
      const first = page.getByRole("table").locator("tbody tr").first().getByRole("link").first();
      const name = (await first.innerText()).trim();
      await first.click();
      await page.getByRole("textbox", { name: "Name", exact: true }).fill(`${name} ${MARKER}`);
      await page.getByRole("button", { name: "Stage change" }).click();
      await expectSaid(page, WORDS.serverFailedUnclearStaged, { alert: true });
      // Never that it staged: the editor stays open with the edit, rather than returning to the list
      // (an earlier test in this file leaves a staged change, so the banner's count can't tell).
      await expect(page).not.toHaveURL(/\/setup\/stations$/);
      await expect(page.getByRole("button", { name: "Stage change" })).toBeVisible();
    });
  });

  test("Add station opens an empty form; Cancel goes back without staging", async ({ page }) => {
    await openConsole(page, screen);
    await page.getByRole("link", { name: "Add station" }).click();
    await expect(page.getByRole("textbox", { name: "Name", exact: true })).toHaveValue("");
    await page.getByRole("link", { name: "Cancel" }).click();
    await expect(page).toHaveURL(/\/setup\/stations$/);
    await expect(page.getByRole("banner")).not.toContainText(/staged/i);
  });
});

test.describe("Ground stations (organization member)", () => {
  test.use({ storageState: storageStateFor("operator") });

  // #1160: staging is any mission operator's (config.stage); the change set is what's reviewed.
  test("can read the list, and add a station for review", async ({ page }) => {
    await openConsole(page, screen);
    await expect(page.getByRole("table").locator("tbody tr")).toHaveCount(10);
    await expect(page.getByRole("link", { name: "Add station" })).toBeVisible();
    await openConsole(page, missionPath("setup/stations/new"));
    await expect(page.getByRole("button", { name: "Stage change" })).toBeVisible();
  });
});
