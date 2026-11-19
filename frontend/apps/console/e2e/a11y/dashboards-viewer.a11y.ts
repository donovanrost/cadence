import { onPhone } from "../support/a11y-projects.ts";
import { authorControl } from "../support/a11y-author.ts";
import { expectAccessible } from "../support/accessibility.ts";
import { openConsole } from "../support/console.ts";
import { firstDashboardPath, holdViewRecords } from "../support/dashboards.ts";
import { expect, test } from "../support/fixtures.ts";
import type { Page } from "@playwright/test";
import { DEV_ONLY, expectKeyboardPass, waitForScreen } from "../support/keyboard.ts";
import { expectSheetChecks } from "../support/sheet.ts";

// #245 per-screen a11y pass: a dashboard's viewer, Kiosk and edit mode, read-only on real data.
// The mission's first dashboard is opened from the directory; its view record is held in the
// browser (holdViewRecords). Edit mode is entered and Tabbed, never saved.
let path: string | null = null;

test.describe("Dashboard viewer · a11y", () => {
  test.beforeEach(async ({ page }) => {
    await holdViewRecords(page);
    path ??= await firstDashboardPath(page);
    if (path === null) return test.skip(true, "no dashboard on this mission");
    await openConsole(page, path);
    await waitForScreen(page);
  });
  const more = (page: Page) => page.getByRole("button", { name: "More dashboard actions" });

  test("axe, one h1, landmarks and the keyboard pass; scrolling widgets are tab stops (B1)", async ({
    page,
  }) => {
    await expectAccessible(page, { exclude: DEV_ONLY });
    await expectKeyboardPass(page);
  });

  test("Time range and Versions pass A1–A5", async ({ page }, info) => {
    // The range button reads the range itself (desktop: in the header; phone: the second row).
    await expectSheetChecks(page, { opener: page.locator("[data-range]"), name: "Time range" });
    await expectSheetChecks(page, {
      opener: more(page),
      via: page.getByRole("menuitem", { name: "Versions" }),
      name: "Versions",
    });
    if (onPhone(info))
      await expectSheetChecks(page, {
        opener: more(page),
        via: page.getByRole("menuitem", { name: /^Refresh: / }),
        name: "Refresh",
      });
  });

  test("Kiosk hands focus to Exit kiosk, and Exit kiosk brings the header back (A5)", async ({
    page,
  }) => {
    await more(page).focus();
    await page.keyboard.press("Enter");
    await page.getByRole("menuitem", { name: "Kiosk" }).focus();
    await page.keyboard.press("Enter");
    const exit = page.getByRole("button", { name: "Exit kiosk" });
    await expect(exit, "A5: focus lands on Exit kiosk, not <body>").toBeFocused();
    await expectAccessible(page, { exclude: DEV_ONLY });
    await page.keyboard.press("Enter");
    await expect(more(page), "the viewer's header is back").toBeVisible();
  });

  test("edit mode: axe and the keyboard pass (B7: controls name their widget and section)", async ({
    page,
  }, info) => {
    test.skip(onPhone(info), "editing is desktop-only (ux Dashboards.md §Phone)");
    const edit = page.locator("[data-edit-dashboard]");
    await authorControl(info, edit, "Edit");
    await edit.focus();
    await page.keyboard.press("Enter");
    await expect(page.getByRole("button", { name: "Save…" })).toBeVisible();
    await waitForScreen(page);
    await expectAccessible(page, { exclude: DEV_ONLY });
    const stops = await expectKeyboardPass(page);
    const unnamed = stops.filter((s) => /^(Move|Edit|Remove)$/i.test(s.name.trim()));
    expect(unnamed, "B7: no bare Move/Edit/Remove without its object").toEqual([]);
  });
});
