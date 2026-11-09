import { expectAccessible } from "./support/accessibility.ts";
import { configState, discardQaChanges, stageRename } from "./support/config.ts";
import { missionPath, openConsole } from "./support/console.ts";
import { expect, test } from "./support/fixtures.ts";

// Changes v1 (fe-setup, 89f15d5d): mission change sets (decision 1). Staging is done through the
// API; the review, withdraw and apply happen in the UI. Every QA change carries MARKER so cleanup
// never touches anyone else's staged work.
const MARKER = "QA-E2E";
const screen = missionPath("setup/changes");
const target = "spacecraft-earendil-499";

// Change sets are mission-wide, so these tests can't run alongside each other.
test.describe.configure({ mode: "serial" });

test.describe("Changes (staged change sets)", () => {
  test.beforeEach(async ({ request }) => {
    const state = await configState(request);
    const set = state["change_set"];
    const foreign =
      typeof set === "object" && set !== null && "staged_count" in set && set.staged_count !== 0;
    test.skip(foreign, "someone else has changes staged on this mission; not touching them");
  });

  test.afterEach(async ({ request }) => {
    await discardQaChanges(request, MARKER);
  });

  test("a staged change shows in the top bar, passes server checks, and can be withdrawn", async ({
    page,
    request,
  }) => {
    await stageRename(request, target, "EARENDIL-499-QA", `${MARKER} rename 499`);
    await openConsole(page, screen);

    await expect(page.getByRole("banner")).toContainText(/config r\d+ · 1 staged/i);
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(/apply r\d+ · 1 change/i);
    await expect(page.getByText(`${MARKER} rename 499`)).toBeVisible();
    await expect(page.getByText(/every change is valid/i)).toBeVisible();

    // Apply needs a reason; the button says so instead of failing on click.
    const apply = page.getByRole("button", { name: /apply as r\d+/i });
    await expect(apply).toHaveAttribute("aria-disabled", "true");
    await expect(apply).toHaveAccessibleDescription(/say why/i);
    await expectAccessible(page);

    await page.getByRole("button", { name: `Withdraw ${MARKER} rename 499` }).click();
    await expect(page.getByText(`${MARKER} rename 499`)).toHaveCount(0);
    await expect(page.getByRole("banner")).not.toContainText(/staged/i);
  });

  test("apply writes a revision with who and why; renaming back writes the next", async ({
    page,
    request,
  }) => {
    test.skip(
      process.env["E2E_MUTATE"] !== "1",
      "writes permanent revisions; run with E2E_MUTATE=1",
    );
    for (const [name, why] of [
      ["EARENDIL-499-QA", `${MARKER} apply check: rename 499 for the revision test`],
      ["EARENDIL-499", `${MARKER} apply check: restore the 499 name`],
    ] as const) {
      await stageRename(request, target, name, `${MARKER} ${name}`);
      await openConsole(page, screen);
      const next = /apply\s+as\s+(r\d+)/i.exec(
        await page.getByRole("button", { name: /apply as r\d+/i }).innerText(),
      )?.[1];
      expect(next, "next revision label").toBeTruthy();
      await page.getByRole("textbox", { name: /why/i }).fill(why);
      await page.getByRole("button", { name: /apply as r\d+/i }).click();
      await expect(page.getByRole("banner")).toContainText(new RegExp(`config ${next}`, "i"));

      await openConsole(page, missionPath("setup/revisions"));
      const row = page.getByRole("row").filter({ hasText: why });
      await expect(row).toHaveCount(1);
      await expect(row).toContainText(next ?? "");
    }
    await openConsole(page, missionPath(`setup/spacecraft/${target}`));
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("EARENDIL-499");
  });
});
