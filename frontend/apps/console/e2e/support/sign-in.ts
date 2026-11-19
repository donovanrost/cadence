import { expect, type Page } from "@playwright/test";

export interface Credentials {
  readonly email: string;
  readonly password: string;
}

const ATTEMPTS = 3;
const BOOT_TIMEOUT_MS = 45_000;

/**
 * Signs in through the console's own sign-in screen (`/console/sign-in`, L5). The old Phoenix
 * `/sign-in` page now 302s here (api-ops ecdddab10), so this is the only login path.
 *
 * On the shared, loaded dev laptop the SPA can take a while to boot; a fresh navigation fixes a
 * stuck boot (the same thing a person would do), so we try up to ATTEMPTS times. The button is
 * scoped to `#main`: the dev-only Tidewave toolbar has its own "Sign in" button.
 */
export async function signIn(page: Page, credentials: Credentials): Promise<void> {
  const email = page.getByLabel("Email", { exact: true });
  for (let attempt = 1; ; attempt += 1) {
    // An aborted navigation just means "try again".
    await page.goto("/console/sign-in").catch(() => undefined);
    const ready = await email
      .waitFor({ state: "visible", timeout: BOOT_TIMEOUT_MS })
      .then(() => true)
      .catch(() => false);
    if (ready) break;
    if (attempt === ATTEMPTS)
      throw new Error(`The console sign-in screen didn't render after ${ATTEMPTS} attempts`);
  }
  await email.fill(credentials.email);
  await page.getByLabel("Password", { exact: true }).fill(credentials.password);
  await page.locator("#main").getByRole("button", { name: "Sign in" }).click();
  await expect(page).not.toHaveURL(/\/sign-in(?:\?|$)/, { timeout: BOOT_TIMEOUT_MS });
}
