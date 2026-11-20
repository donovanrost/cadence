import { expect, test, type Locator, type TestInfo } from "@playwright/test";
import { a11yPersona } from "./a11y-projects.ts";

/**
 * Author-only controls (dashboard.author): the admin projects must find the control; a member
 * without the grant skips, saying so, rather than failing on a control it's right not to have.
 */
export async function authorControl(info: TestInfo, control: Locator, what: string): Promise<void> {
  if (a11yPersona(info) === "admin") {
    await expect(control, `${what}: an organization admin has it`).toBeVisible();
    return;
  }
  test.skip((await control.count()) === 0, `${what}: this member has no dashboard.author`);
}
