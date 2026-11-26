import { guardReadOnly } from "../support/read-only.ts";
import { onPhone } from "../support/a11y-projects.ts";
import { missionPath, openConsole } from "../support/console.ts";
import { expect, test } from "../support/fixtures.ts";
import { waitForScreen } from "../support/keyboard.ts";

test.beforeEach(({ page }) => guardReadOnly(page));

// #868: at 390 Fleet's row list renders only the rows in view (the kit's useRowWindow). Windowing
// must not change what a person gets: the same rows at the same height, Tab through them in order
// with focus never lost, and every craft reachable by scrolling. The seeded fleet has 500 craft.
test.describe("Fleet at 390 · windowed row list", () => {
  test("rows keep their height, Tab order and focus, and the last craft is reachable", async ({
    page,
  }, info) => {
    test.skip(!onPhone(info), "the row list is the phone's Fleet");
    await openConsole(page, missionPath("fleet"));
    await waitForScreen(page);
    const list = page.getByRole("list", { name: "Fleet" });
    const items = list.getByRole("listitem");
    const total = Number(await items.first().getAttribute("aria-setsize"));
    expect(total, "the seeded fleet").toBeGreaterThan(100);
    expect(await items.count(), "only a window renders").toBeLessThan(total);
    for (const height of await items.evaluateAll((li) =>
      li.map((e) => e.getBoundingClientRect().height),
    ))
      expect(height).toBe(75);

    // Tab from the first craft past the first window: each stop is the next craft's name link.
    await items.first().getByRole("link").focus();
    let position = 1;
    for (let i = 0; i < 40; i++) {
      await page.keyboard.press("Tab");
      const next = await page.evaluate(() => {
        const item = document.activeElement?.closest("li[aria-posinset]");
        return item ? Number(item.getAttribute("aria-posinset")) : null;
      });
      expect(next, "focus stays on a craft's link, never <body>").toBe(position + 1);
      position += 1;
    }

    // Every craft is reachable: scroll to the end and the last one is there.
    // The screen scrolls at 390 (the list is no pane of its own); scroll whatever holds the list.
    await list.evaluate((ul) => {
      let node = ul.parentElement;
      while (node && node.scrollHeight <= node.clientHeight) node = node.parentElement;
      (node ?? document.scrollingElement)?.scrollTo(0, Number.MAX_SAFE_INTEGER);
    });
    await expect(list.locator(`li[aria-posinset="${total}"]`)).toBeVisible();
  });
});
