import { openConsole } from "./support/console.ts";
import { DEMO, storageStateFor } from "./support/env.ts";
import { expect, test } from "./support/fixtures.ts";
import type { Page } from "@playwright/test";

// Setup › Settings (director 11-15): a mission's pass review value saves, persists across a reload,
// and goes back to the organization's value. The only browser test of settings. It writes one
// mission-level override ('A pass counts as realized at') and always resets it, in afterEach too,
// so a failed run leaves the mission inheriting again. Locally qa points it at a QA mission
// (E2E_SETTINGS_MISSION_SLUG=qa-mission-23565); CI's seed only has the demo mission.
const missionSlug = process.env["E2E_SETTINGS_MISSION_SLUG"] ?? DEMO.missionSlug;
const screen = `/console/${DEMO.organizationSlug}/${missionSlug}/setup/settings/cadence.pass_review`;
const FIELD = "A pass counts as realized at";

test.use({ storageState: storageStateFor("orgAdmin") });

function field(page: Page) {
  // The field's own block: the nearest ancestor of its label that holds its actions (Override,
  // or Change + Reset to inherited) next to its tag and value.
  return page.getByText(FIELD, { exact: true }).first().locator("xpath=ancestor::*[.//button][1]");
}

async function resetToInherited(page: Page) {
  await openConsole(page, screen);
  // Wait for the section's data before deciding: an overridden field shows Reset to inherited.
  await expect(page.getByText(FIELD, { exact: true }).first()).toBeVisible();
  const reset = field(page).getByRole("button", { name: /reset to inherited/i });
  const overridden = await reset
    .waitFor({ state: "visible", timeout: 3_000 })
    .then(() => true)
    .catch(() => false);
  if (!overridden) return;
  // Pass review resets at once (only governance fields ask to confirm).
  await reset.click();
  await expect(field(page).getByText(/inherited from org/i)).toBeVisible();
}

test.describe("Setup › Settings, pass review", () => {
  test.afterEach(async ({ page }) => {
    await resetToInherited(page);
  });

  test("a mission override saves, survives a reload and resets to the org's value", async ({
    page,
  }) => {
    await openConsole(page, screen);
    await expect(page.getByText("Fleet realization target", { exact: true })).toBeVisible();
    const block = field(page);
    await expect(block.getByText(/inherited from org/i)).toBeVisible();
    const inherited = (await block.innerText()).match(/(\d+)%/)?.[1];
    expect(inherited).toBeTruthy();
    const next = inherited === "90" ? "85" : "90";

    await block.getByRole("button", { name: /^override$/i }).click();
    const input = page.getByRole("textbox", { name: FIELD });
    await input.fill(next);
    await block.getByRole("button", { name: /^save$/i }).click();
    await expect(block.getByText(/inherited from org/i)).toHaveCount(0);
    await expect(block.getByText(`${next}%`)).toBeVisible();

    await page.reload();
    const after = field(page);
    await expect(after.getByText(`${next}%`)).toBeVisible();
    await expect(after.getByText(/inherited from org/i)).toHaveCount(0);

    await resetToInherited(page);
    await expect(field(page).getByText(`${inherited}%`)).toBeVisible();
  });
});
