import { expect, type Locator, type Page } from "@playwright/test";

/**
 * #242 (ux, lead): word-regression checks for the console specs. ux's matching rules (on #242):
 * words are literal, whole sentences from the U-entries, with only whitespace normalized; they come
 * from this one table, never copied into a spec, so a wording change is one edit here.
 */
export const WORDS = {
  /** U20, rejected: the server answered with an error ("staged", "recorded"). */
  rejected: (done: string) => `Nothing was ${done}.`,
  /** U20, outcome unknown: the request may have landed. */
  unclear: (done: string) => `It isn't clear whether anything was ${done}.`,
  /** U20's console form for an act it couldn't confirm ("the grant", "that it resumed"). */
  notConfirmed: (what: string) => `Cadence didn't confirm ${what}. Reload to see it.`,
  /** U25: a spacecraft whose name Cadence can't read; never its id. */
  unknownSpacecraft: "Unknown spacecraft",
  /** U97: an approval the server confirmed (202, outcome approved). */
  approved: (passes: number) => `Approved. Booking ${passes} passes.`,
} as const;

const squash = (s: string) => s.replace(/\s+/g, " ").trim();

/** The texts of every live region of one kind on the page, whitespace normalized. */
async function regionTexts(page: Page, kind: "alert" | "status"): Promise<string[]> {
  const texts = await page.getByRole(kind).allTextContents();
  return texts.map(squash);
}

/**
 * a11y B6: how the words are said, and that what's shown is what's said (ux).
 * - `alert`: a refusal or failure of the person's act. In an alert region, and in no polite one.
 * - otherwise a success, said politely: in a status region (the kit's announcer, #604, or a
 *   status line), and in no alert region. It is also shown on the page, in the same words.
 */
export async function expectSaid(
  page: Page,
  words: string,
  how: { alert: boolean },
): Promise<void> {
  const sentence = squash(words);
  const said = how.alert ? "alert" : "status";
  const other = how.alert ? "status" : "alert";
  await expect
    .poll(async () => (await regionTexts(page, said)).some((t) => t.includes(sentence)), {
      message: `"${sentence}" is said in a ${said} region`,
    })
    .toBe(true);
  expect(
    (await regionTexts(page, other)).some((t) => t.includes(sentence)),
    `"${sentence}" is not also said in a ${other} region`,
  ).toBe(false);
  await expect(page.getByText(sentence).first(), `"${sentence}" is shown`).toBeVisible();
}

/**
 * U20: after a stubbed failure, the failure line (the caller's U20 sentence) is said as an alert,
 * and the success words appear nowhere: not shown, and not said in any region.
 */
export async function expectNoFalseSuccess(
  page: Page,
  outcome: { failure: string; success: string },
): Promise<void> {
  await expectSaid(page, outcome.failure, { alert: true });
  const success = squash(outcome.success);
  await expect(page.getByText(success)).toHaveCount(0);
  for (const kind of ["alert", "status"] as const) {
    expect(
      (await regionTexts(page, kind)).some((t) => t.includes(success)),
      `"${success}" is not said in a ${kind} region`,
    ).toBe(false);
  }
}

/**
 * U25: a nameless spacecraft reads as "Unknown spacecraft", and its raw id appears only inside a
 * Technical details disclosure: not in the text, nor in an aria-* or title attribute, elsewhere.
 */
export async function expectNameFallback(page: Page, rawId: string): Promise<void> {
  await expect(page.getByText(WORDS.unknownSpacecraft).first()).toBeVisible();
  const leaks = await page.locator("body").evaluate((body, id) => {
    const copy = body.cloneNode(true) as HTMLElement;
    // Not shown to anyone: scripts, styles and templates can carry ids that are never read.
    for (const hidden of copy.querySelectorAll("script, style, template, noscript"))
      hidden.remove();
    for (const d of copy.querySelectorAll("details")) {
      if (/technical details/i.test(d.querySelector("summary")?.textContent ?? "")) d.remove();
    }
    const found: string[] = [];
    if (copy.textContent?.includes(id)) found.push("text");
    for (const el of copy.querySelectorAll("*")) {
      for (const attr of Array.from(el.attributes)) {
        if ((attr.name.startsWith("aria-") || attr.name === "title") && attr.value.includes(id))
          found.push(`${el.tagName.toLowerCase()}[${attr.name}]`);
      }
    }
    return found;
  }, rawId);
  expect(leaks, `the raw id ${rawId} appears outside Technical details`).toEqual([]);
}

/** B7 and U107: a control's accessible name, in the words ux gave it (e.g. "Discard, EARENDIL-001, …"). */
export async function expectNamed(control: Locator, name: string): Promise<void> {
  await expect(control).toHaveAccessibleName(squash(name));
}
