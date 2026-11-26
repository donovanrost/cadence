import { guardReadOnly } from "../support/read-only.ts";
import { authorControl } from "../support/a11y-author.ts";
import { expectAccessible } from "../support/accessibility.ts";
import { missionPath, openConsole } from "../support/console.ts";
import { firstRowLink } from "../support/dashboards.ts";
import { test } from "../support/fixtures.ts";
import { DEV_ONLY, expectKeyboardPass, waitForScreen } from "../support/keyboard.ts";
import { expectSheetChecks } from "../support/sheet.ts";

// qa's :4011 condition: only reads reach the server (support/read-only.ts).
test.beforeEach(({ page }) => guardReadOnly(page));

// #245 per-screen a11y pass: Dashboards' directory, Library and Playlists, read-only on real data
// (loads, Tabs, opens and closes sheets with Esc; never acts). Checklist: docs/apogee/ux/a11y-checklist.md.
const screens = [
  ["Directory", "telemetry/dashboards"],
  ["Library", "telemetry/dashboards/library"],
  ["Playlists", "telemetry/dashboards/playlists"],
] as const;

test.describe("Dashboards lists · a11y", () => {
  for (const [label, path] of screens) {
    test(`${label}: axe, one h1, landmarks and the keyboard pass (B1)`, async ({ page }) => {
      await openConsole(page, missionPath(path));
      await waitForScreen(page);
      await expectAccessible(page, { exclude: DEV_ONLY });
      await expectKeyboardPass(page);
    });
  }

  test("Directory: a row's Duplicate… and Archive… sheets pass A1–A5", async ({ page }, info) => {
    const name = await firstRowLink(page, "telemetry/dashboards");
    if (name === null) return test.skip(true, "no dashboard on this mission");
    const row = (await name.textContent())?.trim() ?? "";
    const opener = page.getByRole("button", { name: `Actions for ${row}`, exact: true });
    await opener.click(); // the row menu: Star is anyone's, Duplicate… and Archive… an author's
    await authorControl(info, page.getByRole("menuitem", { name: "Duplicate…" }), "Duplicate…");
    await page.keyboard.press("Escape");
    const dialog = page.getByRole("dialog", { name: "Duplicate dashboard" });
    await expectSheetChecks(page, {
      opener,
      via: page.getByRole("menuitem", { name: "Duplicate…" }),
      name: "Duplicate dashboard",
      initialFocus: dialog.getByRole("textbox"),
    });
    await expectSheetChecks(page, {
      opener,
      via: page.getByRole("menuitem", { name: "Archive…" }),
      name: `Archive ${row}?`,
    });
  });

  test("Library: a widget's Rename… sheet passes A1–A5", async ({ page }, info) => {
    const name = await firstRowLink(page, "telemetry/dashboards/library");
    if (name === null) return test.skip(true, "no library widget on this mission");
    const row = (await name.textContent())?.trim() ?? "";
    const opener = page.getByRole("button", { name: `Actions for ${row}`, exact: true });
    await authorControl(info, opener, "a library widget's actions");
    const dialog = page.getByRole("dialog", { name: "Rename library widget" });
    await expectSheetChecks(page, {
      opener,
      via: page.getByRole("menuitem", { name: "Rename…" }),
      name: "Rename library widget",
      initialFocus: dialog.getByRole("textbox"),
    });
  });

  test("Playlists: the New playlist sheet passes A1–A5", async ({ page }, info) => {
    await openConsole(page, missionPath("telemetry/dashboards/playlists"));
    await waitForScreen(page);
    const opener = page.getByRole("main").getByRole("button", { name: "New playlist" });
    await authorControl(info, opener, "New playlist");
    const dialog = page.getByRole("dialog", { name: "New playlist" });
    await expectSheetChecks(page, {
      opener,
      name: "New playlist",
      initialFocus: dialog.getByRole("textbox").first(),
    });
  });
});
