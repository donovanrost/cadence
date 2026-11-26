import { expectAccessible } from "./support/accessibility.ts";
import { missionPath, openConsole } from "./support/console.ts";
import { expectSaid, WORDS } from "./support/outcomes.ts";
import { allow, expect, test } from "./support/fixtures.ts";
import { bumpTemplate, liveDraftDays, plansForDay, utcDay } from "./support/planning.ts";

// K1 · Submit races a contact-rule change (lead, d212c8f1). The submit sheet is open on a draft;
// another tab saves a new version of a template the draft took up; Submit answers 409
// plan_superseded. Nothing may be booked: the sheet closes onto the superseded state.
//
// Writes permanently (a template version and, when the day has no draft, a draft), so opt-in.
// Day: four days out, clear of today's bookings. The template version supersedes EVERY open draft
// that took the template up (all days in the horizon), so the test skips while any other day holds
// a live draft: someone may be reviewing it.
const DAY = utcDay(4);
const screen = missionPath(`contacts/plan?day=${DAY}`);
const DRAFT_TIMEOUT = 8 * 60_000;

test.describe("K1 submit loses a race with a contact-rule change", () => {
  test.use({
    // The 409 is the behaviour under test; the browser logs it as a failed resource.
    allowedDiagnostics: allow(/\/submit -> 409/, /status of 409/),
  });

  test("409 plan_superseded closes the sheet; nothing is submitted; Draft again leads", async ({
    page,
    request,
  }) => {
    test.skip(
      process.env["E2E_MUTATE"] !== "1",
      "saves a template version (and may draft a day); run with E2E_MUTATE=1",
    );
    test.setTimeout(DRAFT_TIMEOUT + 3 * 60_000);
    const others = await liveDraftDays(request, DAY);
    test.skip(others.length > 0, `live drafts on ${others.join(", ")} would be superseded too`);
    await openConsole(page, screen);

    const submit = page.getByRole("button", {
      name: /^(submit and book|accept \d+ gaps? and submit)/i,
    });
    const draft = page.getByRole("button", { name: /^draft (the day|again)/i });
    await expect(submit.or(draft).first()).toBeVisible({ timeout: 45_000 });
    if (!(await submit.isVisible())) {
      await draft.first().click();
      await expect(submit).toBeVisible({ timeout: DRAFT_TIMEOUT });
    }

    await submit.click();
    const sheet = page.getByRole("dialog");
    await expect(sheet).toBeVisible();
    // Gaps need a reason; one reason for all of them (qa #27, 10ffd37d).
    const sameReason = sheet.getByRole("checkbox", { name: "Same reason for all" });
    if (await sameReason.count()) {
      await sameReason.check();
      await sheet
        .getByRole("textbox", { name: /reason for accepting all \d+ gaps/i })
        .fill("QA-E2E submit race: gaps accepted for the test");
    }

    // "Another tab": a new version of EARENDIL-001's template supersedes the draft.
    expect(await bumpTemplate(request, "EARENDIL-001", `QA-E2E submit race ${Date.now()}`)).toBe(
      201,
    );

    const answer = page.waitForResponse(
      (r) => r.request().method() === "POST" && /\/contact-plans\/[^/]+\/submit$/.test(r.url()),
    );
    await sheet
      .getByRole("button", { name: /submit/i })
      .last()
      .click();
    const response = await answer;
    expect(response.status()).toBe(409);
    expect(await response.json()).toMatchObject({ error: { code: "plan_superseded" } });

    await expect(page.getByRole("dialog")).toHaveCount(0);
    await expect(page.getByText(/Nothing was submitted\.$/)).toBeVisible();
    // #654 (B6): the refusal of the person's own Submit is an alert, not read politely.
    await expectSaid(page, WORDS.nothingSubmitted, { alert: true });
    await expect(
      page.getByRole("button", { name: "Draft again with the current rules" }),
    ).toBeVisible();
    await expect(submit).toHaveCount(0);

    const [current] = await plansForDay(request, DAY);
    expect(current?.["state"]).toBe("superseded");

    await expectAccessible(page);
  });
});
