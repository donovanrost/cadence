import type { Page } from "@playwright/test";
import { expectAccessible } from "./support/accessibility.ts";
import { missionPath, openConsole } from "./support/console.ts";
import { expect, test } from "./support/fixtures.ts";

// J5 · ⌘K query line (fe-ops, 1ffbfce8/70c35227). Ctrl+K is accepted alongside ⌘K, so the spec is
// platform-independent.
const dialog = (page: Page) => page.getByRole("dialog", { name: "Search and run commands" });
const query = (page: Page) => dialog(page).getByRole("combobox", { name: "Search" });

test.describe("Palette (J5)", () => {
  test.beforeEach(async ({ page }) => {
    await openConsole(page, missionPath("now"));
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  });

  test("Ctrl+K opens it focused; '312' puts EARENDIL-312 first; Enter opens it", async ({
    page,
  }) => {
    await page.keyboard.press("Control+k");
    await expect(dialog(page)).toBeVisible();
    await expect(query(page)).toBeFocused();

    await query(page).fill("312");
    const first = dialog(page).getByRole("option").first();
    await expect(first).toContainText("EARENDIL-312");
    // The highlighted option is announced through aria-activedescendant.
    const active = await query(page).getAttribute("aria-activedescendant");
    expect(active, "an option is active").toBeTruthy();
    await expect(first).toHaveAttribute("id", active ?? "");

    await page.keyboard.press("Enter");
    await expect(dialog(page)).toHaveCount(0);
    await expect(page).toHaveURL(/\/fleet\/312(?:\/|$)/);
  });

  test("Ctrl+Enter commands the spacecraft instead of opening it", async ({ page }) => {
    await page.keyboard.press("Control+k");
    await query(page).fill("312");
    await expect(dialog(page).getByRole("option").first()).toContainText("EARENDIL-312");
    await page.keyboard.press("Control+Enter");
    await expect(page).toHaveURL(/command/i);
    await expect(page).toHaveURL(/312/);
  });

  test("'/' opens it; Esc closes and returns focus where it was", async ({ page }) => {
    const trigger = page.getByRole("link", { name: /now/i }).first();
    await trigger.focus();
    await page.keyboard.press("/");
    await expect(dialog(page)).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(dialog(page)).toHaveCount(0);
    await expect(trigger).toBeFocused();
  });

  test("is accessible when open", async ({ page }) => {
    await page.keyboard.press("Control+k");
    await expect(dialog(page).getByRole("option").first()).toBeVisible();
    await expectAccessible(page);
  });

  test("Tab keeps focus inside the modal dialog", async ({ page }) => {
    await page.keyboard.press("Control+k");
    await expect(query(page)).toBeFocused();
    for (let i = 0; i < 8; i += 1) {
      await page.keyboard.press("Tab");
      const inside = await dialog(page).evaluate((el) => el.contains(document.activeElement));
      expect(inside, `focus after ${i + 1} Tab(s)`).toBe(true);
    }
  });

  test("an unknown query says nothing matched", async ({ page }) => {
    await page.keyboard.press("Control+k");
    await query(page).fill("zzzz-no-such-thing");
    await expect(dialog(page).getByRole("option")).toHaveCount(0);
    await expect(dialog(page)).toContainText(/no (?:results|matches)|nothing/i);
  });

  test("G C and G N chords navigate", async ({ page }) => {
    await page.locator("body").click({ position: { x: 5, y: 5 } });
    await page.keyboard.press("g");
    await page.keyboard.press("c");
    await expect(page).toHaveURL(/\/contacts(?:[/?#]|$)/);
    await page.keyboard.press("g");
    await page.keyboard.press("n");
    await expect(page).toHaveURL(/\/now(?:[/?#]|$)/);
  });
});
