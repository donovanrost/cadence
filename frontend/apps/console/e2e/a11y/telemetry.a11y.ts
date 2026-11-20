import { guardReadOnly } from "../support/read-only.ts";
import { expectAccessible } from "../support/accessibility.ts";
import { missionPath, openConsole } from "../support/console.ts";
import { onPhone } from "../support/a11y-projects.ts";
import { test } from "../support/fixtures.ts";
import { DEV_ONLY, expectKeyboardPass, waitForScreen } from "../support/keyboard.ts";

// qa's :4011 condition: only reads reach the server (support/read-only.ts).
test.beforeEach(({ page }) => guardReadOnly(page));

// #245 per-screen a11y pass: Telemetry › Explore, read-only (loads and Tabs; the points search
// is a POST read, but nothing here types into it).
test.describe("Telemetry Explore · a11y", () => {
  test("axe, one h1, landmarks and the keyboard pass (B1, B2)", async ({ page }, info) => {
    test.skip(
      !!process.env["CI"] && onPhone(info),
      "#637: at 390 the sticky T1 Points header covers the Explore and Dashboards tab links",
    );
    await openConsole(page, missionPath("telemetry"));
    await waitForScreen(page);
    await expectAccessible(page, { exclude: DEV_ONLY });
    await expectKeyboardPass(page);
  });
});
