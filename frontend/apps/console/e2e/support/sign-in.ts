import { expect, request, type Page } from "@playwright/test";

export interface Credentials {
  readonly email: string;
  readonly password: string;
}

const ATTEMPTS = 3;
const BOOT_TIMEOUT_MS = 45_000;

/**
 * Signs in through the console's own sign-in screen (`/console/sign-in`), the only login path.
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

/**
 * Signs in through the console's sign-in API and saves the session to `path` (storageState), with
 * no page at all (#242, director): a password typed into a page ends up in Playwright's traces,
 * HAR and video, which CI uploads from a public repo. A standalone request context isn't traced.
 * The CSRF token comes from the console document's meta tag, as the SPA reads it.
 */
export async function signInByApi(
  baseURL: string,
  credentials: Credentials,
  path: string,
): Promise<void> {
  const api = await request.newContext({ baseURL });
  try {
    const page = await api.get("/console/sign-in");
    expect(page.ok(), "the console document loads").toBe(true);
    const csrf = /<meta[^>]+name="csrf-token"[^>]+content="([^"]+)"/.exec(await page.text())?.[1];
    expect(csrf, "the console document carries a CSRF token").toBeTruthy();
    const res = await api.post("/api/v1/auth/sign-in", {
      headers: { "x-csrf-token": csrf ?? "", accept: "application/json" },
      data: { email: credentials.email, password: credentials.password },
    });
    // Never print the request: only the status says what went wrong.
    expect(res.status(), `signing in as ${credentials.email}`).toBe(200);
    await api.storageState({ path });
  } finally {
    await api.dispose();
  }
}
