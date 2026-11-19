import { openConsole } from "./support/console.ts";
import { PERSONAS, storageStateFor } from "./support/env.ts";
import { allow, expect, test } from "./support/fixtures.ts";

// L6 admin mode (Auth.md, Admin.md): a password step-up for platform administration. Replaces the
// legacy admin_mode browser smoke, whose page went in L6. Writes only the session's admin-mode
// grant, which this spec leaves again; nothing permanent. The wrong password's 422 is the point.
test.use({
  storageState: storageStateFor("admin"),
  allowedDiagnostics: allow(/session\/admin-mode -> 422/, /status of 422.*session\/admin-mode/),
});

test.describe("admin mode", () => {
  test("a wrong password is refused, the right one enters, and leaving ends it", async ({
    page,
  }) => {
    await openConsole(page, "/console");
    const accountMenu = page.getByRole("button", { name: /account menu/i });

    // Start outside admin mode, whatever an earlier run left behind.
    await accountMenu.click();
    const leaveFirst = page.getByRole("menuitem", { name: "Leave admin mode" });
    if (await leaveFirst.isVisible()) {
      await leaveFirst.click();
      await accountMenu.click();
    }
    // The account menu is a menu button (design-language §6): its items are menuitems.
    await page.getByRole("menuitem", { name: "Enter admin mode" }).click();

    const form = page.locator("dialog[open]").last();
    const password = form.getByLabel("Password", { exact: true });
    const submit = form.getByRole("button", { name: "Enter admin mode" });

    await password.fill("not-the-admin-password");
    await submit.click();
    await expect(form.getByText("That password isn't right.")).toBeVisible();
    await expect(form).toBeVisible();

    await password.fill(PERSONAS.admin.password);
    await submit.click();
    await expect(form).toBeHidden();

    await accountMenu.click();
    await expect(page.getByRole("menuitem", { name: "Admin area" })).toBeVisible();
    await page.getByRole("menuitem", { name: "Leave admin mode" }).click();

    await accountMenu.click();
    await expect(page.getByRole("menuitem", { name: "Enter admin mode" })).toBeVisible();
    await expect(page.getByRole("menuitem", { name: "Leave admin mode" })).toHaveCount(0);
  });
});
