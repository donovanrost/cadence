import { guardReadOnly } from "../support/read-only.ts";
import { onPhone } from "../support/a11y-projects.ts";
import { expectAccessible } from "../support/accessibility.ts";
import { missionPath, openConsole } from "../support/console.ts";
import { expect, test } from "../support/fixtures.ts";
import { DEV_ONLY, expectKeyboardPass, waitForScreen } from "../support/keyboard.ts";
import { expectSheetChecks } from "../support/sheet.ts";

// qa's :4011 condition: only reads reach the server (support/read-only.ts).
test.beforeEach(({ page }) => guardReadOnly(page));

// #189 per-screen a11y pass, the example each owner copies (#241). It runs in the four a11y
// projects (1440 and 390, admin and member), read-only on real data: it loads, Tabs, opens and
// closes, and never acts. Checklist: docs/apogee/ux/a11y-checklist.md (A, B, D).
test.describe("Now · a11y", () => {
  test.beforeEach(async ({ page }) => {
    await openConsole(page, missionPath("now"));
    await waitForScreen(page);
  });

  test("axe, one h1, landmarks and the keyboard pass (B1, §6)", async ({ page }, info) => {
    await expectAccessible(page, { exclude: DEV_ONLY });
    const stops = await expectKeyboardPass(page);

    // B1 reading order: the top bar and rail come before the page; at 390 the tab bar after it (D1).
    const runs = stops.map((s) => s.landmark).filter((l, i, all) => all[i - 1] !== l);
    const main = runs.indexOf("main");
    expect(main, "Tab reaches the page").toBeGreaterThan(0);
    expect(runs.slice(0, main), "the top bar comes before the page").toContain("banner");
    if (onPhone(info))
      expect(runs.slice(main + 1), "the tab bar comes after the page (D1)").toContain(
        "navigation 'On-call tabs'",
      );
    else
      expect(runs.slice(0, main), "the rail comes before the page").toContain("navigation 'Ops'");
  });

  test("the search palette passes A1–A5", async ({ page }, info) => {
    // Desktop opens the palette from the top bar's query line; a phone opens the full-screen
    // Search sheet from the tab bar, with a searchbox instead of the palette's combobox.
    const phone = onPhone(info);
    const opener = phone
      ? page
          .getByRole("navigation", { name: "On-call tabs" })
          .getByRole("button", { name: "Search" })
      : page.getByRole("banner").locator('button[aria-keyshortcuts~="Control+K"]');
    const name = phone ? "Search" : "Search and run commands";
    const dialog = page.getByRole("dialog", { name, exact: true });
    await expectSheetChecks(page, {
      opener,
      name,
      initialFocus: dialog.getByRole(phone ? "searchbox" : "combobox", { name: "Search" }),
    });
  });
});
