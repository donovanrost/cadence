import type { Locator, Page } from "@playwright/test";
import { missionPath, openConsole } from "./support/console.ts";
import { expect, test } from "./support/fixtures.ts";

// Top bar give-way (ux information-architecture.md §Top bar, f144e8fab, 660a1d06d; lead, qa):
// when the bar tightens, the posture goes compact, then the brand, the crumb's org, the query and
// the extra clocks give way, and the last resort is a second row. Nothing is ever clipped: the
// account menu and UTC stay fully on screen. Read-only.

async function fullyInView(page: Page, target: Locator) {
  const box = await target.boundingBox();
  const width = page.viewportSize()?.width ?? 0;
  expect(box, "on screen").not.toBeNull();
  if (!box) return;
  expect(box.x).toBeGreaterThanOrEqual(0);
  expect(box.x + box.width).toBeLessThanOrEqual(width + 0.5);
}

for (const width of [1100, 1280]) {
  for (const [mode, path] of [
    ["Ops", missionPath("")],
    ["Setup", missionPath("setup")],
  ] as const) {
    test(`${mode} at ${width}px: the account menu and UTC are fully on screen`, async ({
      page,
    }) => {
      await page.setViewportSize({ width, height: 900 });
      await openConsole(page, path);
      const banner = page.getByRole("banner");
      await expect(banner).toBeVisible();
      // The bar settles in a few frames; then nothing may overflow it sideways.
      await expect
        .poll(() => banner.evaluate((h) => h.scrollWidth <= h.clientWidth + 1))
        .toBe(true);
      await fullyInView(page, page.getByRole("button", { name: /account menu/i }));
      await fullyInView(page, banner.getByText("UTC", { exact: true }));
    });
  }
}
