import { expect, type Page } from "@playwright/test";

export interface Credentials {
  readonly email: string;
  readonly password: string;
}

/** Signs in through the real Phoenix /sign-in page, the console's only login path. */
export async function signIn(page: Page, credentials: Credentials): Promise<void> {
  await page.goto("/sign-in");
  const form = page.locator("#sign-in-form");
  await form.locator("#user_email").fill(credentials.email);
  await form.locator("#user_password").fill(credentials.password);
  await form.locator('button[type="submit"]').click();
  await expect(page).not.toHaveURL(/\/sign-in(?:\?|$)/);
}
