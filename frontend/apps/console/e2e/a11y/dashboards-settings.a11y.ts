import { guardReadOnly } from "../support/read-only.ts";
import { a11yPersona } from "../support/a11y-projects.ts";
import { expectAccessible } from "../support/accessibility.ts";
import { openConsole } from "../support/console.ts";
import { firstDashboardPath, holdViewRecords } from "../support/dashboards.ts";
import { expect, test } from "../support/fixtures.ts";
import { DEV_ONLY, expectKeyboardPass, waitForScreen } from "../support/keyboard.ts";

// qa's :4011 condition: only reads reach the server (support/read-only.ts).
test.beforeEach(({ page }) => guardReadOnly(page));

// #245 per-screen a11y pass: a dashboard's Settings, every tab the persona has (an author:
// General, Sharing, Activity, Diagnostics; anyone else: Activity and Diagnostics). Read-only:
// each tab is loaded and Tabbed; no confirm is opened past its Cancel.
let path: string | null = null;

test.describe("Dashboard settings · a11y", () => {
  test("each tab: axe, one h1, landmarks and the keyboard pass", async ({ page }, info) => {
    await holdViewRecords(page);
    path ??= await firstDashboardPath(page);
    if (path === null) return test.skip(true, "no dashboard on this mission");
    await openConsole(page, `${path}/settings`);
    await waitForScreen(page);
    const tabs = page.getByRole("navigation", { name: "Settings sections" }).getByRole("link");
    const hrefs = await tabs.evaluateAll((links) => links.map((a) => a.getAttribute("href") ?? ""));
    if (a11yPersona(info) === "admin")
      expect(hrefs.length, "an organization admin sees all four tabs").toBe(4);
    else expect(hrefs.length, "at least Activity and Diagnostics").toBeGreaterThanOrEqual(2);

    for (const href of hrefs) {
      await test.step(href.split("/").at(-1) ?? href, async () => {
        await openConsole(page, href);
        await waitForScreen(page);
        await expectAccessible(page, { exclude: DEV_ONLY });
        await expectKeyboardPass(page);
      });
    }
  });
});
