import { expect, type Page } from "@playwright/test";

export interface Credentials {
  readonly email: string;
  readonly password: string;
}

const ATTEMPTS = 3;
const MOUNT_TIMEOUT_MS = 15_000;

/**
 * Signs in through the real Phoenix /sign-in page, the console's only login path.
 *
 * On the shared, loaded dev laptop the LiveView socket sometimes misses its 2.5 s WebSocket
 * window, falls back to long polling and never mounts the form; a reload fixes it (the same thing
 * a person would do). So we wait for LiveView to connect and reload up to ATTEMPTS times.
 */
export async function signIn(page: Page, credentials: Credentials): Promise<void> {
  for (let attempt = 1; ; attempt += 1) {
    if (attempt === 1) await page.goto("/sign-in");
    else await page.reload();
    const connected = await page
      .locator(".phx-connected")
      .first()
      .waitFor({ state: "attached", timeout: MOUNT_TIMEOUT_MS })
      .then(() => true)
      .catch(() => false);
    if (connected) break;
    if (attempt === ATTEMPTS)
      throw new Error(`LiveView sign-in didn't connect after ${ATTEMPTS} attempts`);
  }
  const form = page.locator("#sign-in-form");
  await form.locator("#user_email").fill(credentials.email);
  await form.locator("#user_password").fill(credentials.password);
  await form.locator('button[type="submit"]').click();
  await expect(page).not.toHaveURL(/\/sign-in(?:\?|$)/);
}
