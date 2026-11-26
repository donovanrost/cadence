import { guardReadOnly } from "../support/read-only.ts";
import { expectAccessible } from "../support/accessibility.ts";
import { missionPath, openConsole } from "../support/console.ts";
import { holdViewRecords } from "../support/dashboards.ts";
import { expect, test } from "../support/fixtures.ts";
import { DEV_ONLY, waitForScreen } from "../support/keyboard.ts";

// qa's :4011 condition: only reads reach the server (support/read-only.ts).
test.beforeEach(({ page }) => guardReadOnly(page));

// #245 per-screen a11y pass: Present, read-only. It opens the first playlist's Present from the
// keyboard, checks one h1 and axe, and leaves with Esc; focus returns to that playlist's Present
// link (A5). Present has no <main> page to Tab, so the keyboard pass isn't run here.
test.describe("Present · a11y", () => {
  test("axe, one h1; Esc leaves to the Present link (A5)", async ({ page }) => {
    await holdViewRecords(page);
    await openConsole(page, missionPath("telemetry/dashboards/playlists"));
    await waitForScreen(page);
    const present = page.locator("[data-present]").first();
    if ((await present.count()) === 0) return test.skip(true, "no playlist on this mission");
    const id = await present.getAttribute("data-present");
    await present.focus();
    await page.keyboard.press("Enter");
    await expect(page).toHaveURL(/\/present$/);
    await waitForScreen(page);
    await expect(page.locator("h1"), "one h1").toHaveCount(1);
    await expectAccessible(page, { exclude: DEV_ONLY });

    await page.keyboard.press("Escape");
    await expect(page).toHaveURL(/\/playlists$/);
    await expect(
      page.locator(`[data-present="${id}"]`),
      "A5: focus returns to the playlist's Present link",
    ).toBeFocused();
  });
});
