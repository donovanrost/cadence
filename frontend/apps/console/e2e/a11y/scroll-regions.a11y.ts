import AxeBuilder from "@axe-core/playwright";
import { onPhone } from "../support/a11y-projects.ts";
import { missionPath, openConsole } from "../support/console.ts";
import { expect, test } from "../support/fixtures.ts";
import { DEV_ONLY, waitForScreen } from "../support/keyboard.ts";

// qa a11y run 2, findings #1 and #2 (390 only): a table or the wizard's step bar scrolled sideways
// with no tab stop, role or name (axe scrollable-region-focusable). The kit fix (8fa0f9e9e) landed
// after the run; this rechecks the screens with stable routes. Read-only: loads only.
const screens = [
  ["spacecraft detail (#1)", "setup/spacecraft/spacecraft-earendil-001"],
  ["profile History (#1)", "setup/profiles/profile-earendil-block-1/history"],
  ["new spacecraft wizard (#2)", "setup/spacecraft/new"],
] as const;

test.describe("Run 2 #1 and #2 · scrolling regions at 390", () => {
  for (const [label, path] of screens) {
    test(label, async ({ page }, info) => {
      test.skip(!onPhone(info), "a 390 finding");
      await openConsole(page, missionPath(path));
      await waitForScreen(page);
      let axe = new AxeBuilder({ page }).withRules(["scrollable-region-focusable"]);
      for (const selector of DEV_ONLY) axe = axe.exclude(selector);
      const { violations } = await axe.analyze();
      const targets = violations.flatMap((v) => v.nodes.map((n) => n.target.join(" ")));
      expect(targets, "scrolling regions without a tab stop").toEqual([]);
    });
  }
});
