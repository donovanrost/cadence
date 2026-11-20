import { expect, type Locator, type Page } from "@playwright/test";

/**
 * #242 (ux, lead): word-regression checks for the console specs, to ux's matching rules on #242.
 * Words are literal, whole sentences from the U-entries, with only whitespace normalized.
 *
 * WORDS holds exact U-entry sentences only, each with its entry (ux on #648): a spec takes its words
 * from here, never types them, so a wording change is one edit. Add a sentence when a spec needs
 * it, citing its U-entry, with ux's review.
 */
export const WORDS = {
  /** U20 (rejected): "Nothing was staged." */
  nothingStaged: "Nothing was staged.",
  // U20's outcome-unknown words appear only mid-sentence, with a cause ("The connection dropped, so
  // it isn't clear …"): add those real sentences, cited, when a spec needs one (ux on #648).
  /** U25 and #237: a spacecraft whose name Cadence can't read, never its id. */
  unknownSpacecraft: "Unknown spacecraft",
  /** U97: "Approved. Booking 40 passes." only on the 202 with outcome approved; N is the count. */
  approved: (passes: number) => `Approved. Booking ${passes} passes.`,
  /**
   * U20 (outcome unknown) with qa #19: a 5xx after a write may have committed, so it's unclear, never
   * "nothing changed". As the console words it (changes' failureOutcome), one literal per verb
   * (ux on #648: literal entries only).
   */
  serverFailedUnclearStaged:
    "The server failed while answering, so it isn't clear whether anything was staged. Check Staged changes and Revisions now, before trying again.",
  /** As above, for a write that changes rather than stages (the policy save). */
  serverFailedUnclearChanged:
    "The server failed while answering, so it isn't clear whether anything was changed. Check Staged changes and Revisions now, before trying again.",
  /** CP2 policy save (U20's success line; PolicyTab): the second sentence of "Saved as vN. …". */
  policyPendingActivation: "It's active once another admin approves it.",
  /** CP2 policy decision, `reviewer_is_author` (PolicyDecision): the version's author can't approve it. */
  policyAuthorCantApprove:
    "Nothing was changed. You saved this version, so another admin must approve it.",
} as const;

/** ux: polite is role=status or aria-live=polite; alert is role=alert or aria-live=assertive. */
const REGIONS = {
  status: '[role="status"], [aria-live="polite"]',
  alert: '[role="alert"], [aria-live="assertive"]',
} as const;

const squash = (s: string) => s.replace(/\s+/g, " ").trim();

async function saidIn(page: Page, kind: keyof typeof REGIONS, sentence: string): Promise<boolean> {
  const texts = await page.locator(REGIONS[kind]).allTextContents();
  return texts.some((t) => squash(t).includes(sentence));
}

/**
 * Shown means on screen for a sighted person: in an element outside the kit's announcer
 * ([data-ap-announcer]) and any .sr-only text, with a box bigger than a pixel and not hidden.
 * Playwright counts the 1px sr-only announcer as visible, so it can't be the check (lead, ux on
 * #648).
 */
async function shown(page: Page, sentence: string): Promise<boolean> {
  return page.evaluate((s) => {
    const squashed = (t: string | null) => (t ?? "").replace(/\s+/g, " ").trim();
    for (const el of document.body.querySelectorAll<HTMLElement>("*")) {
      if (el.closest("[data-ap-announcer], .sr-only, script, style, template")) continue;
      if (!squashed(el.textContent).includes(s)) continue;
      // The innermost element holding the whole sentence.
      if (Array.from(el.children).some((c) => squashed(c.textContent).includes(s))) continue;
      const box = el.getBoundingClientRect();
      const style = getComputedStyle(el);
      if (box.width > 1 && box.height > 1 && style.visibility !== "hidden" && style.opacity !== "0")
        return true;
    }
    return false;
  }, sentence);
}

/**
 * a11y B6: how the words are said, and that what's shown is what's said (ux).
 * - `alert`: a refusal or failure of the person's act. In an alert region, and in no polite one.
 * - otherwise a success, said politely: in a polite region and in no alert one.
 * Either way the same words are shown on screen.
 */
export async function expectSaid(
  page: Page,
  words: string,
  how: { alert: boolean; timeout?: number },
): Promise<void> {
  const sentence = squash(words);
  const said = how.alert ? "alert" : "status";
  const other = how.alert ? "status" : "alert";
  const timeout = how.timeout ?? 15_000;
  await expect
    .poll(() => saidIn(page, said, sentence), {
      message: `"${sentence}" is said (${said})`,
      timeout,
    })
    .toBe(true);
  expect(await saidIn(page, other, sentence), `"${sentence}" is not also said (${other})`).toBe(
    false,
  );
  await expect
    .poll(() => shown(page, sentence), { message: `"${sentence}" is shown on screen`, timeout })
    .toBe(true);
}

/**
 * U20: after a stubbed failure, the failure line (the caller's U20 sentence) is said as an alert,
 * and the success words are neither shown nor said in any region.
 */
export async function expectNoFalseSuccess(
  page: Page,
  outcome: { failure: string; success: string; timeout?: number },
): Promise<void> {
  await expectSaid(page, outcome.failure, {
    alert: true,
    ...(outcome.timeout === undefined ? {} : { timeout: outcome.timeout }),
  });
  const success = squash(outcome.success);
  expect(await shown(page, success), `"${success}" is not shown`).toBe(false);
  for (const kind of ["alert", "status"] as const) {
    expect(await saidIn(page, kind, success), `"${success}" is not said (${kind})`).toBe(false);
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
