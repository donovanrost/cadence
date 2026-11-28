import type { Page } from "@playwright/test";
import { expectAccessible } from "./support/accessibility.ts";
import { missionPath, openConsole } from "./support/console.ts";
import { DEMO, storageStateFor } from "./support/env.ts";
import { expect, test } from "./support/fixtures.ts";

// S2 · Add spacecraft wizard (fe-setup). The batch is staged into the mission change set
// (decision 1); nothing here clicks Stage, so nothing is written. The draft lives in sessionStorage per mission.
const wizard = missionPath("setup/spacecraft/new");

async function chooseProfile(page: Page) {
  await page.getByRole("radio", { name: /Earendil Block 1/ }).check();
  await page.getByRole("button", { name: "Continue to identity" }).click();
  await expect(page.getByRole("textbox", { name: "Count" })).toBeVisible();
}

async function continueTo(page: Page, step: string) {
  await page.getByRole("button", { name: `Continue to ${step}` }).click();
}

test.describe("Add spacecraft wizard, organization admin", () => {
  test("preselects the only profile; an invalid count blocks Continue and says why", async ({
    page,
  }) => {
    await openConsole(page, wizard);
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(/add spacecraft/i);
    await expect(page.getByRole("radio", { name: /Earendil Block 1/ })).toBeChecked();
    await expectAccessible(page);

    await page.getByRole("button", { name: "Continue to identity" }).click();
    await page.getByRole("textbox", { name: "Count" }).fill("0");
    const next = page.getByRole("button", { name: "Continue to orbit & routing" });
    await expect(next).toHaveAttribute("aria-disabled", "true");
    await expect(next).toHaveAccessibleDescription(/count from 1 to/i);
    // Clicking a disabled step button does nothing.
    await next.click({ force: true });
    await expect(page.getByRole("textbox", { name: "Count" })).toBeVisible();
  });

  test("walks a 4-spacecraft batch to review; stage is enabled when every check passes", async ({
    page,
  }) => {
    await openConsole(page, wizard);
    await chooseProfile(page);

    // Prefilled with the next free SCID after the seeded fleet.
    await expect(page.getByRole("textbox", { name: "First SCID" })).toHaveValue(
      String(DEMO.spacecraftCount + 1),
    );
    await page.getByRole("textbox", { name: "Count" }).fill("4");
    await page.getByRole("textbox", { name: "Naming pattern" }).fill("QA-SC-{n:03}");
    await expectAccessible(page);

    await continueTo(page, "orbit & routing");
    await expect(page.getByRole("heading", { name: "Orbit & routing" })).toBeVisible();
    await continueTo(page, "review");

    const identityCheck = page.getByRole("listitem").filter({ hasText: "unique in this mission" });
    await expect(identityCheck).toHaveCount(1);
    await expect(identityCheck).toContainText("Pass");
    await expect(page.getByText("Batch preview")).toBeVisible();
    await expect(page.getByText("QA-SC-001")).toBeVisible();

    // Staging writes to the mission change set; this spec stops short of it (see changes.e2e.ts).
    const stage = page.getByRole("button", { name: "Stage 4 spacecraft" });
    await expect(stage).toBeVisible();
    await expect(stage).not.toHaveAttribute("aria-disabled", "true");
    await expectAccessible(page);
  });

  test("flags SCIDs that clash with the existing fleet", async ({ page }) => {
    await openConsole(page, wizard);
    await chooseProfile(page);
    await page.getByRole("textbox", { name: "First SCID" }).fill(String(DEMO.spacecraftCount - 1));
    await page.getByRole("textbox", { name: "Count" }).fill("4");
    await page.getByRole("textbox", { name: "Naming pattern" }).fill("QA-CLASH-{n:03}");
    // Two of four collide with seeded SCIDs (499, 500).
    await expect(
      page.getByText(new RegExp(`\\b${DEMO.spacecraftCount - 1}\\b`)).first(),
    ).toBeVisible();
    await continueTo(page, "orbit & routing");
    await continueTo(page, "review");
    await expect(page.getByText("NO-GO").first()).toBeVisible();
    const stage = page.getByRole("button", { name: /^Stage/ });
    await expect(stage).toHaveAttribute("aria-disabled", "true");
    await expect(stage).toHaveAccessibleDescription(/Fix \d+ NO-GO checks? first/);
  });

  test("keeps the draft across a reload, and the close button keeps it too", async ({ page }) => {
    await openConsole(page, wizard);
    await chooseProfile(page);
    await page.getByRole("textbox", { name: "Count" }).fill("7");
    await page.reload();
    await expect(page.locator("body[data-shell-ready]")).toBeAttached();
    // The step is in the URL and the draft in sessionStorage: same step, same values.
    await expect(page.getByRole("textbox", { name: "Count" })).toHaveValue("7");
    await page.getByRole("button", { name: "Back to source" }).click();
    await expect(page.getByRole("radio", { name: /Earendil Block 1/ })).toBeChecked();

    await page.getByRole("link", { name: "Close and keep draft" }).click();
    await expect(page).toHaveURL(/\/setup\/spacecraft$/);
  });
});

test.describe("Add spacecraft wizard, organization member", () => {
  test.use({ storageState: storageStateFor("operator") });

  // #1160: adding spacecraft stages a reviewed change, so any mission operator may (config.stage).
  test("may stage: no role refusal on the page or on Stage", async ({ page }) => {
    await openConsole(page, wizard);
    await chooseProfile(page);
    await continueTo(page, "orbit & routing");
    await continueTo(page, "review");
    const stage = page.getByRole("button", { name: /^Stage/ });
    await expect(stage).toBeVisible();
    await expect(stage).not.toHaveAccessibleDescription(
      "Only mission operators can add spacecraft.",
    );
    await expect(page.getByText("Only mission operators can add spacecraft")).toHaveCount(0);
  });
});
