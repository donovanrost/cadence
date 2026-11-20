import { expect, test } from "@playwright/test";
import { expectNameFallback, expectNoFalseSuccess, expectSaid, WORDS } from "./support/outcomes.ts";

/**
 * #242 (lead on #648): the word checks fail when they should, on static pages (page.setContent),
 * with no server. The sr-only announcer is styled as the kit's is: 1px, clipped.
 */
const SR_ONLY =
  "position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0";
const announcer = (text: string) =>
  `<div data-ap-announcer role="status" class="sr-only" style="${SR_ONLY}">${text}</div>`;
const quick = { timeout: 500 } as const;

test.describe("outcomes helper self-test", () => {
  // Static pages only: no session, no server.
  test.use({ storageState: { cookies: [], origins: [] } });

  test("a success announced and shown passes", async ({ page }) => {
    const s = WORDS.approved(40);
    await page.setContent(`<main><p>${s}</p>${announcer(s)}</main>`);
    await expectSaid(page, s, { alert: false, ...quick });
  });

  test("announced but never shown fails (lead)", async ({ page }) => {
    const s = WORDS.approved(40);
    await page.setContent(`<main>${announcer(s)}</main>`);
    await expect(expectSaid(page, s, { alert: false, ...quick })).rejects.toThrow(/shown/);
  });

  test("a refusal said both as an alert and politely fails", async ({ page }) => {
    const s = WORDS.nothingStaged;
    await page.setContent(`<main><p role="alert">${s}</p><p aria-live="polite">${s}</p></main>`);
    await expect(expectSaid(page, s, { alert: true, ...quick })).rejects.toThrow(/not also said/);
  });

  test("an aria-live=assertive region counts as an alert (ux)", async ({ page }) => {
    const s = WORDS.nothingStaged;
    await page.setContent(`<main><p aria-live="assertive">${s}</p></main>`);
    await expectSaid(page, s, { alert: true, ...quick });
  });

  test("a success shown after a failure is a false success", async ({ page }) => {
    await page.setContent(
      `<main><p role="alert">${WORDS.unclearStaged}</p><p>${WORDS.approved(40)}</p></main>`,
    );
    await expect(
      expectNoFalseSuccess(page, {
        failure: WORDS.unclearStaged,
        success: WORDS.approved(40),
        ...quick,
      }),
    ).rejects.toThrow(/is not shown/);
  });

  test("a raw id in an aria-label outside Technical details fails; inside, it passes", async ({
    page,
  }) => {
    const id = "spacecraft-qa-9";
    await page.setContent(
      `<main><p>${WORDS.unknownSpacecraft}</p><details><summary>Technical details</summary>${id}</details></main>`,
    );
    await expectNameFallback(page, id);
    await page.setContent(
      `<main><button aria-label="Open ${id}">${WORDS.unknownSpacecraft}</button></main>`,
    );
    await expect(expectNameFallback(page, id)).rejects.toThrow(/outside Technical details/);
  });
});
