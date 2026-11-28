import { expectAccessible } from "./support/accessibility.ts";
import { jsonProblem, missionApi, missionPath, openConsole } from "./support/console.ts";
import { storageStateFor } from "./support/env.ts";
import { allow, expect, test } from "./support/fixtures.ts";
import { expectNoFalseSuccess, expectSaid, WORDS } from "./support/outcomes.ts";

// CP2 · Contact planning policy (fe-setup). Saving creates a pending version that another admin
// approves or rejects. The seeded policy (dev/seed/planning.exs): 48 h horizon,
// 1,000 contacts per plan.
const screen = missionPath("setup/contact-planning/policy");
// GET /contact-planning (summary) isn't built yet; the page copes, the browser logs the 404.
const summary404 = allow(/\/contact-planning -> 404/, /status of 404/);

test.describe("Contact planning policy, organization admin", () => {
  test.use({
    allowedDiagnostics: allow(
      /\/contact-planning -> 404/,
      /status of 404/,
      /\/decision -> 409/,
      /status of 409/,
    ),
  });

  test("shows the active policy's values", async ({ page }) => {
    await openConsole(page, screen);
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(/contact planning/i);
    await expect(page.getByRole("textbox", { name: /longest planning window/i })).toHaveValue(
      "48h 00m",
    );
    await expect(page.getByRole("textbox", { name: /contacts per plan/i })).toHaveValue("1000");
    await expect(page.getByRole("button", { name: /save as v\d+/i })).toBeVisible();
    await expectAccessible(page);
  });

  test("save → pending; the author can't approve; another admin rejects", async ({
    page,
    browser,
  }) => {
    test.skip(process.env["E2E_MUTATE"] !== "1", "creates a policy version; run with E2E_MUTATE=1");
    test.setTimeout(120_000);
    await openConsole(page, screen);
    await page.getByRole("textbox", { name: /contacts per plan/i }).fill("1001");
    await page.getByRole("textbox", { name: "Why" }).fill("QA-E2E pending-version check");
    await page.getByRole("button", { name: /save as v\d+/i }).click();
    // #644 (B6): the save's success is said politely ("Saved as vN. It's active once …").
    await expectSaid(page, WORDS.policyPendingActivation, { alert: false });
    const waiting = page.getByRole("region", { name: /waiting for approval/i }).or(
      page
        .locator("section, div")
        .filter({ has: page.getByRole("heading", { name: /waiting for approval/i }) })
        .last(),
    );
    await expect(waiting.first()).toBeVisible();

    // The server requires a comment for any decision (qa #21).
    await page.getByRole("textbox", { name: "Comment" }).fill("QA-E2E self-approval attempt");
    await page.getByRole("button", { name: /^approve v\d+/i }).click();
    // #644 (B6): the refusal of the author's own approval is an alert.
    await expectSaid(page, WORDS.policyAuthorCantApprove, { alert: true });

    // Clean up: a different admin (platform admin) rejects it; the active policy never changed.
    const other = await browser.newContext({ storageState: storageStateFor("admin") });
    const reviewer = await other.newPage();
    await openConsole(reviewer, screen);
    await reviewer.getByRole("textbox", { name: "Comment" }).fill("QA-E2E reject");
    await reviewer.getByRole("button", { name: "Reject" }).click();
    await expect(reviewer.getByRole("heading", { name: /waiting for approval/i })).toHaveCount(0);
    await expect(reviewer.getByRole("textbox", { name: /contacts per plan/i })).toHaveValue("1000");
    await other.close();
  });
});

test.describe("Contact planning policy, a save the server fails on", () => {
  test.use({
    allowedDiagnostics: allow(
      /\/contact-planning -> 404/,
      /status of 404/,
      /\/policy -> 500/,
      /status of 500/,
    ),
  });

  // #644 (U20, B6): a 5xx may have committed, so it's said as unclear, an alert, and the success
  // line ("…It's active once another admin approves it.") is neither shown nor said. The POST is
  // stubbed, so no version is created.
  test("is said as unclear, never as saved", async ({ page }) => {
    await page.route(missionApi("contact-planning/policy"), (route) =>
      route.request().method() === "POST"
        ? route.fulfill(jsonProblem(500, "internal_error"))
        : route.continue(),
    );
    await openConsole(page, screen);
    await page.getByRole("textbox", { name: /contacts per plan/i }).fill("1001");
    await page.getByRole("button", { name: /save as v\d+/i }).click();
    await expectNoFalseSuccess(page, {
      failure: WORDS.policySaveUnclear,
      success: WORDS.policyPendingActivation,
    });
  });
});

test.describe("Contact planning policy, organization member", () => {
  test.use({ storageState: storageStateFor("operator"), allowedDiagnostics: summary404 });

  test("can't save a new version (manage_fleet_planning_policy needs organization admin)", async ({
    page,
  }) => {
    await openConsole(page, screen);
    await expect(page.getByRole("textbox", { name: /contacts per plan/i })).toBeVisible();
    await expect(page.getByRole("button", { name: /save as v\d+/i })).toHaveCount(0);
  });
});
